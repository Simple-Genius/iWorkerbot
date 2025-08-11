////
////  VectorDataBase.swift
////  ChatBot
////
////  Created by Ajila Ibrahim Adeboye on 7/24/25.
////

import Foundation
import SQLite
import os.log
import Accelerate

class SQLiteVectorStore {
    private var db: Connection
    private let logger = Logger(subsystem: "com.chatbot.vectorstore", category: "SQLite")
    private let queue = DispatchQueue(label: "com.chatbot.vectordb", attributes: .concurrent)
    
    // Configuration
    private let vectorDimension = 768  // DistilBERT dimension
    
    // Table definitions
    private let vectors = Table("vectors")
    private let documents = Table("documents")
    
    // Vector table columns
    private let id = Expression<Int64>("id")
    private let documentId = Expression<String>("document_id")
    private let chunkIndex = Expression<Int>("chunk_index")
    private let chunkText = Expression<String>("chunk_text")
    private let embedding = Expression<Data>("embedding")
    private let magnitude = Expression<Double>("magnitude")
    private let vectorCreatedAt = Expression<Date>("created_at")
    
    // Document table columns
    private let docId = Expression<String>("document_id")
    private let title = Expression<String?>("title")
    private let totalChunks = Expression<Int>("total_chunks")
    private let modelVersion = Expression<String?>("model_version")
    private let docCreatedAt = Expression<Date>("created_at")
    
    enum VectorStoreError: LocalizedError {
        case databaseError(String)
        case serializationError
        case invalidDimension
        case notFound
        case connectionError
        
        var errorDescription: String? {
            switch self {
            case .databaseError(let msg): return "Database error: \(msg)"
            case .serializationError: return "Failed to serialize/deserialize vector"
            case .invalidDimension: return "Invalid vector dimension"
            case .notFound: return "Vector not found"
            case .connectionError: return "Database connection error"
            }
        }
    }
    
    init(dbName: String = "vectors.db") throws {
        // Get documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                    in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent(dbName).path
        
        do {
            self.db = try Connection(dbPath)
            // logger.info("Database opened at: \(dbPath)")
            
            try createTables()
            try optimizeDatabase()
        } catch {
            throw VectorStoreError.connectionError
        }
    }
    
    // MARK: - Database Setup
    
    private func createTables() throws {
        do {
            // Create vectors table
            try db.run(vectors.create(ifNotExists: true) { t in
                t.column(id, primaryKey: .autoincrement)
                t.column(documentId)
                t.column(chunkIndex)
                t.column(chunkText)
                t.column(embedding)
                t.column(magnitude)
                t.column(vectorCreatedAt, defaultValue: Date())
                t.unique([documentId, chunkIndex])
            })
            
            // Create documents table
            try db.run(documents.create(ifNotExists: true) { t in
                t.column(docId, primaryKey: true)
                t.column(title)
                t.column(totalChunks)
                t.column(modelVersion)
                t.column(docCreatedAt, defaultValue: Date())
            })
            
            // Create indices
            try db.run(vectors.createIndex(documentId, ifNotExists: true))
            try db.run(vectors.createIndex(magnitude, ifNotExists: true))
            try db.run(vectors.createIndex(vectorCreatedAt, ifNotExists: true))
            
            // logger.info("Tables and indices created successfully")
            
        } catch {
            throw VectorStoreError.databaseError("Failed to create tables: \(error)")
        }
    }
    
    private func optimizeDatabase() throws {
        do {
            try db.execute("PRAGMA page_size = 4096")
            try db.execute("PRAGMA cache_size = -2000")  // 2MB cache
            try db.execute("PRAGMA temp_store = MEMORY")
            try db.execute("PRAGMA mmap_size = 30000000000")  // 30MB memory-mapped I/O
            try db.execute("PRAGMA synchronous = NORMAL")
            try db.execute("PRAGMA journal_mode = WAL")
            
            // logger.info("Database optimizations applied")
        } catch {
            logger.warning("Failed to apply database optimizations: \(error)")
        }
    }
    
    // MARK: - Core Operations
    
    /// Add a vector to the store
    func addVector(
        documentId: String,
        chunkIndex: Int,
        chunkText: String,
        embedding: [Float],
        modelVersion: String = "distilbert-v1"
    ) throws {
        guard embedding.count == vectorDimension else {
            throw VectorStoreError.invalidDimension
        }
        
        try queue.sync(flags: .barrier) {
            // Calculate magnitude for faster similarity computation
            let mag = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
            
            // Serialize embedding
            let embeddingData = try serializeVector(embedding)
            
            // Insert or replace vector
            let insert = vectors.insert(or: .replace,
                self.documentId <- documentId,
                self.chunkIndex <- chunkIndex,
                self.chunkText <- chunkText,
                self.embedding <- embeddingData,
                self.magnitude <- Double(mag)
            )
            
            try db.run(insert)
            
            // Update document metadata
            try updateDocumentMetadata(documentId: documentId, modelVersion: modelVersion)
        }
    }
    
    /// Add multiple vectors in a batch (more efficient)
    func addVectorsBatch(
        documentId: String,
        chunks: [(index: Int, text: String, embedding: [Float])],
        modelVersion: String = "distilbert-v1"
    ) throws {
        try queue.sync(flags: .barrier) {
            try db.transaction {
                for chunk in chunks {
                    // Calculate magnitude for faster similarity computation
                    let mag = sqrt(chunk.embedding.map { $0 * $0 }.reduce(0, +))
                    
                    // Serialize embedding
                    let embeddingData = try serializeVector(chunk.embedding)
                    
                    // Insert or replace vector
                    let insert = vectors.insert(or: .replace,
                        self.documentId <- documentId,
                        self.chunkIndex <- chunk.index,
                        self.chunkText <- chunk.text,
                        self.embedding <- embeddingData,
                        self.magnitude <- Double(mag)
                    )
                    
                    try db.run(insert)
                }
                
                // Update document metadata once after all inserts
                try updateDocumentMetadata(documentId: documentId, modelVersion: modelVersion)
            }
            
            // logger.info("Batch inserted \(chunks.count) vectors for document: \(documentId)")
        }
    }
    
    /// Search for similar vectors
    func search(
        queryEmbedding: [Float],
        topK: Int = 5,
        documentId: String? = nil
    ) throws -> [(chunkText: String, score: Float, metadata: ChunkMetadata)] {
        guard queryEmbedding.count == vectorDimension else {
            throw VectorStoreError.invalidDimension
        }
        
        return try queue.sync {
            let queryMagnitude = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
            
            // Build query with optional document filter
            var query = vectors.select(id, self.documentId, chunkIndex, chunkText, embedding, magnitude)
                .order(vectorCreatedAt.desc)
                .limit(1000)  // Limit candidates
            
            if let docId = documentId {
                query = query.filter(self.documentId == docId)
            }
            
            var results: [(chunkText: String, score: Float, metadata: ChunkMetadata)] = []
            
            for row in try db.prepare(query) {
                autoreleasepool {
                    let vectorId = row[id]
                    let docId = row[self.documentId]
                    let chunkIdx = row[chunkIndex]
                    let text = row[chunkText]
                    let embeddingData = row[embedding]
                    let mag = row[magnitude]
                    
                    // Deserialize embedding
                    if let vectorEmbedding = try? deserializeVector(embeddingData) {
                        // Calculate cosine similarity
                        let dotProduct = zip(queryEmbedding, vectorEmbedding)
                            .map { $0 * $1 }
                            .reduce(0, +)
                        let similarity = dotProduct / (queryMagnitude * Float(mag) + 1e-8)
                        
                        let metadata = ChunkMetadata(
                            id: Int(vectorId),
                            documentId: docId,
                            chunkIndex: chunkIdx
                        )
                        
                        results.append((chunkText: text, score: similarity, metadata: metadata))
                    }
                }
            }
            
            // Sort by similarity and return top K
            return Array(results.sorted { $0.score > $1.score }.prefix(topK))
        }
    }
    
    /// Clear vectors for a document (for reprocessing)
    func clearDocument(documentId: String) throws {
        try queue.sync(flags: .barrier) {
            try db.run(vectors.filter(self.documentId == documentId).delete())
            try db.run(documents.filter(docId == documentId).delete())
            // logger.info("Cleared document: \(documentId)")
        }
    }
    
    /// Delete all vectors for a document
    func deleteDocument(_ documentId: String) throws {
        try clearDocument(documentId: documentId)
    }
    
    /// Get document statistics
    func getDocumentStats() throws -> [DocumentStats] {
        return try queue.sync {
            let query = """
                SELECT d.document_id, d.title, d.total_chunks, d.created_at,
                       COUNT(v.document_id) as actual_chunks
                FROM documents d
                LEFT JOIN vectors v ON d.document_id = v.document_id
                GROUP BY d.document_id
                ORDER BY d.created_at DESC
            """
            
            var stats: [DocumentStats] = []
            
            for row in try db.prepare(query) {
                let docId = row[0] as! String
                let title = row[1] as? String
                let totalChunks = row[2] as! Int64
                let createdAt = row[3] as! String
                let actualChunks = row[4] as! Int64
                
                stats.append(DocumentStats(
                    documentId: docId,
                    title: title,
                    totalChunks: Int(totalChunks),
                    actualChunks: Int(actualChunks),
                    createdAt: createdAt
                ))
            }
            
            return stats
        }
    }
    
    /// Check if document exists
    func documentExists(_ documentId: String) throws -> Bool {
        return try queue.sync {
            let count = try db.scalar(documents.filter(docId == documentId).count)
            return count > 0
        }
    }
    
    /// Get total vector count for a document
    func getVectorCount(for documentId: String) throws -> Int {
        return try queue.sync {
            let count = try db.scalar(vectors.filter(self.documentId == documentId).count)
            return count
        }
    }
    
    // MARK: - Helper Methods
    
    private func serializeVector(_ vector: [Float]) throws -> Data {
        return vector.withUnsafeBytes { bytes in
            Data(bytes)
        }
    }
    
    private func deserializeVector(_ data: Data) throws -> [Float] {
        guard data.count == vectorDimension * MemoryLayout<Float>.size else {
            throw VectorStoreError.serializationError
        }
        
        return data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }
    
    private func updateDocumentMetadata(documentId: String, modelVersion: String) throws {
        // Count vectors for this document
        let chunkCount = try db.scalar(vectors.filter(self.documentId == documentId).count)
        
        // Insert or replace document metadata
        let insert = documents.insert(or: .replace,
            docId <- documentId,
            totalChunks <- chunkCount,
            self.modelVersion <- modelVersion
        )
        
        try db.run(insert)
    }
    
    // MARK: - Data Models
    
    struct ChunkMetadata {
        let id: Int
        let documentId: String
        let chunkIndex: Int
    }
    
    struct DocumentStats {
        let documentId: String
        let title: String?
        let totalChunks: Int
        let actualChunks: Int
        let createdAt: String
    }
}

// MARK: - Optimized Vector Operations

extension SQLiteVectorStore {
    /// Compute similarity using SIMD for better performance
    static func cosineSimilaritySIMD(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        
        // Use vDSP for optimized vector operations
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &magnitudeA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &magnitudeB, vDSP_Length(b.count))
        
        return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB) + 1e-8)
    }
}

// MARK: - Migration Support

extension SQLiteVectorStore {
    /// Check and perform database migrations if needed
    func migrate() throws {
        let currentVersion = try getDatabaseVersion()
        
        if currentVersion < 2 {
            // Add migration logic here for future versions
            // logger.info("Database is up to date (version: \(currentVersion))")
        }
    }
    
    private func getDatabaseVersion() throws -> Int {
        let version = try db.scalar("PRAGMA user_version") as! Int64
        return Int(version)
    }
    
    /// Set database version
    func setDatabaseVersion(_ version: Int) throws {
        try db.execute("PRAGMA user_version = \(version)")
    }
}

// MARK: - Advanced Query Methods

extension SQLiteVectorStore {
    /// Search with metadata filtering
    func searchWithFilter(
        queryEmbedding: [Float],
        topK: Int = 5,
        documentIds: [String]? = nil,
        minScore: Float = 0.0
    ) throws -> [(chunkText: String, score: Float, metadata: ChunkMetadata)] {
        guard queryEmbedding.count == vectorDimension else {
            throw VectorStoreError.invalidDimension
        }
        
        return try queue.sync {
            let queryMagnitude = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
            
            // Build query with filters
            var query = vectors.select(id, documentId, chunkIndex, chunkText, embedding, magnitude)
                .order(vectorCreatedAt.desc)
                .limit(2000)  // Larger candidate pool for filtering
            
            if let docIds = documentIds, !docIds.isEmpty {
                query = query.filter(docIds.contains(documentId))
            }
            
            var results: [(chunkText: String, score: Float, metadata: ChunkMetadata)] = []
            
            for row in try db.prepare(query) {
                autoreleasepool {
                    let vectorId = row[id]
                    let docId = row[self.documentId]
                    let chunkIdx = row[chunkIndex]
                    let text = row[chunkText]
                    let embeddingData = row[embedding]
                    let mag = row[magnitude]
                    
                    // Deserialize embedding
                    if let vectorEmbedding = try? deserializeVector(embeddingData) {
                        // Calculate cosine similarity
                        let dotProduct = zip(queryEmbedding, vectorEmbedding)
                            .map { $0 * $1 }
                            .reduce(0, +)
                        let similarity = dotProduct / (queryMagnitude * Float(mag) + 1e-8)
                        
                        // Apply minimum score filter
                        if similarity >= minScore {
                            let metadata = ChunkMetadata(
                                id: Int(vectorId),
                                documentId: docId,
                                chunkIndex: chunkIdx
                            )
                            
                            results.append((chunkText: text, score: similarity, metadata: metadata))
                        }
                    }
                }
            }
            
            // Sort by similarity and return top K
            return Array(results.sorted { $0.score > $1.score }.prefix(topK))
        }
    }
    
    /// Get all document IDs
    func getAllDocumentIds() throws -> [String] {
        return try queue.sync {
            let query = documents.select(docId)
            return try db.prepare(query).map { $0[docId] }
        }
    }
    
    /// Clear all data
    func clearAll() throws {
        try queue.sync(flags: .barrier) {
            try db.transaction {
                try db.run(vectors.delete())
                try db.run(documents.delete())
            }
            // logger.info("Cleared all data from vector store")
        }
    }
}

