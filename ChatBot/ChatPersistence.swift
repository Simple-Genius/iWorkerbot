//
//  ChatPersistence.swift
//  ChatBot
//
//  Created by Ajila Ibrahim Adeboye on 7/25/25.
//

import Foundation
import SQLite

/// Manages persistent storage of chat conversations

class ChatPersistenceManager {
    
    // MARK: - Database properties
    private let db: Connection
    private let chatMessages = Table("chat_messages")
    private let chatSessions = Table("chat_sessions")
    
    // MARK: - Column definitions
    private let id = Expression<Int64>("id")
    private let sessionId = Expression<String>("session_id")
    private let message = Expression<String>("message")
    private let isUser = Expression<Bool>("is_user")
    private let timestamp = Expression<Date>("timestamp")
    
    private let documentId = Expression<String?>("document_id")
    private let createdAt = Expression<Date>("created_at")
    private let lastAccessed = Expression<Date>("last_accessed")

    // MARK: - Init
    init() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documentsPath.appendingPathComponent("chats.db")
        db = try Connection(dbURL.path)
        try createTables()
    }

    // MARK: - Table creation
    private func createTables() throws {
        // chat_messages table
        try db.run(chatMessages.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(sessionId)
            t.column(message)
            t.column(isUser)
            t.column(timestamp, defaultValue: Date())
        })

        // chat_sessions table
        try db.run(chatSessions.create(ifNotExists: true) { t in
            t.column(sessionId, primaryKey: true)
            t.column(documentId)
            t.column(createdAt, defaultValue: Date())
            t.column(lastAccessed, defaultValue: Date())
        })

        // Index
        try db.run(chatMessages.createIndex(sessionId, ifNotExists: true))
    }

    // MARK: - Save message
    func saveMessage(sessionId: String, message: String, isUser: Bool) {
        let insert = chatMessages.insert(
            self.sessionId <- sessionId,
            self.message <- message,
            self.isUser <- isUser,
            self.timestamp <- Date()
        )
        try? db.run(insert)
    }

    // MARK: - Load messages
    func loadMessages(for sessionId: String) -> [String] {
        var messages: [String] = []

        do {
            let query = chatMessages
                .filter(self.sessionId == sessionId)
                .order(self.timestamp.asc)

            for row in try db.prepare(query) {
                let msg = row[self.message]
                let senderPrefix = row[self.isUser] ? "[USER]" : ""
                messages.append(senderPrefix + msg)
            }
        } catch {
           // // print("Error loading messages: \(error)")
        }

        return messages.isEmpty ? ["Welcome to Worker Bot"] : messages
    }

    // MARK: - Clear history
    func clearHistory(for sessionId: String) {
        let delete = chatMessages.filter(self.sessionId == sessionId).delete()
        try? db.run(delete)
    }
}
