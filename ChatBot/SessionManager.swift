////
////  SessionManager.swift
////  ChatBot
////
////  Session Management System for Multi-language RAG Chatbot
////
//
//import Foundation
//import SQLite
//import SwiftUI
//
//
//// MARK: - Language Extension for Codable
//
//extension Language: Codable {
//    // Language enum already has String raw values, so it automatically conforms to Codable
//}
//
//// MARK: - Session Models
//
//struct ChatSession: Identifiable, Codable {
//    let id: String
//    let title: String
//    let language: Language
//    let createdAt: Date
//    let lastAccessed: Date
//    let messageCount: Int
//    
//    var displayTitle: String {
//        if title.isEmpty {
//            return language == .english ? "New Chat" : "Новый чат"
//        }
//        return title
//    }
//    
//    var formattedDate: String {
//        let formatter = DateFormatter()
//        formatter.dateStyle = .medium
//        formatter.timeStyle = .short
//        return formatter.string(from: lastAccessed)
//    }
//}
//
//enum SessionError: LocalizedError {
//    case sessionNotFound
//    case databaseError(String)
//    case invalidSession
//    
//    var errorDescription: String? {
//        switch self {
//        case .sessionNotFound:
//            return "Session not found"
//        case .databaseError(let message):
//            return "Database error: \(message)"
//        case .invalidSession:
//            return "Invalid session"
//        }
//    }
//}
//
//// MARK: - Session Manager
//
//class SessionManager: ObservableObject {
//    @Published var sessions: [ChatSession] = []
//    @Published var currentSession: ChatSession?
//    
//    private let db: Connection
//    private let sessionsTable = Table("chat_sessions")
//    
//    // Session table columns
//    private let sessionId = Expression<String>("session_id")
//    private let title = Expression<String>("title")
//    private let language = Expression<String>("language")
//    private let createdAt = Expression<Date>("created_at")
//    private let lastAccessed = Expression<Date>("last_accessed")
//    private let messageCount = Expression<Int>("message_count")
//    
//    init() throws {
//        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        let dbURL = documentsPath.appendingPathComponent("sessions.db")
//        
//        self.db = try Connection(dbURL.path)
//        try createSessionsTable()
//        try loadSessions()
//    }
//    
//    // MARK: - Database Setup
//    
//    private func createSessionsTable() throws {
//        try db.run(sessionsTable.create(ifNotExists: true) { t in
//            t.column(sessionId, primaryKey: true)
//            t.column(title)
//            t.column(language)
//            t.column(createdAt)
//            t.column(lastAccessed)
//            t.column(messageCount, defaultValue: 0)
//        })
//        
//        // Create indices
//        try db.run(sessionsTable.createIndex(lastAccessed, ifNotExists: true))
//        try db.run(sessionsTable.createIndex(language, ifNotExists: true))
//    }
//    
//    // MARK: - Session Operations
//    
//    func createNewSession(language: Language = .english, title: String? = nil) throws -> ChatSession {
//        let sessionId = generateSessionId()
//        let sessionTitle = title ?? ""
//        let now = Date()
//        
//        let session = ChatSession(
//            id: sessionId,
//            title: sessionTitle,
//            language: language,
//            createdAt: now,
//            lastAccessed: now,
//            messageCount: 0
//        )
//        
//        // Insert into database
//        let insert = sessionsTable.insert(
//            self.sessionId <- sessionId,
//            self.title <- sessionTitle,
//            self.language <- language.rawValue,
//            self.createdAt <- now,
//            self.lastAccessed <- now,
//            self.messageCount <- 0
//        )
//        
//        try db.run(insert)
//        
//        // Update local state
//        DispatchQueue.main.async {
//            self.sessions.insert(session, at: 0)
//            self.currentSession = session
//        }
//        
//        return session
//    }
//    
//    func switchToSession(_ session: ChatSession) throws {
//        // Update last accessed time
//        try updateLastAccessed(sessionId: session.id)
//        
//        DispatchQueue.main.async {
//            self.currentSession = session
//        }
//    }
//    
//    func deleteSession(_ session: ChatSession) throws {
//        // Delete from database
//        try db.run(sessionsTable.filter(sessionId == session.id).delete())
//        
//        // Update local state
//        DispatchQueue.main.async {
//            self.sessions.removeAll { $0.id == session.id }
//            
//            // If we deleted the current session, switch to the most recent one
//            if self.currentSession?.id == session.id {
//                self.currentSession = self.sessions.first
//            }
//        }
//    }
//    
//    func updateSessionTitle(_ session: ChatSession, newTitle: String) throws {
//        let update = sessionsTable
//            .filter(sessionId == session.id)
//            .update(title <- newTitle)
//        
//        try db.run(update)
//        
//        // Update local state
//        DispatchQueue.main.async {
//            if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
//                var updatedSession = self.sessions[index]
//                self.sessions[index] = ChatSession(
//                    id: updatedSession.id,
//                    title: newTitle,
//                    language: updatedSession.language,
//                    createdAt: updatedSession.createdAt,
//                    lastAccessed: updatedSession.lastAccessed,
//                    messageCount: updatedSession.messageCount
//                )
//                
//                if self.currentSession?.id == session.id {
//                    self.currentSession = self.sessions[index]
//                }
//            }
//        }
//    }
//    
//    func updateMessageCount(_ session: ChatSession, increment: Int = 1) throws {
//        let currentCount = session.messageCount
//        let newCount = currentCount + increment
//        
//        let update = sessionsTable
//            .filter(sessionId == session.id)
//            .update(
//                messageCount <- newCount,
//                lastAccessed <- Date()
//            )
//        
//        try db.run(update)
//        
//        // Update local state
//        DispatchQueue.main.async {
//            if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
//                let updatedSession = self.sessions[index]
//                self.sessions[index] = ChatSession(
//                    id: updatedSession.id,
//                    title: updatedSession.title,
//                    language: updatedSession.language,
//                    createdAt: updatedSession.createdAt,
//                    lastAccessed: Date(),
//                    messageCount: newCount
//                )
//                
//                if self.currentSession?.id == session.id {
//                    self.currentSession = self.sessions[index]
//                }
//            }
//        }
//    }
//    
//    // MARK: - Helper Methods
//    
//    private func loadSessions() throws {
//        let query = sessionsTable.order(lastAccessed.desc)
//        var loadedSessions: [ChatSession] = []
//        
//        for row in try db.prepare(query) {
//            let session = ChatSession(
//                id: row[sessionId],
//                title: row[title],
//                language: Language(rawValue: row[language]) ?? .english,
//                createdAt: row[createdAt],
//                lastAccessed: row[lastAccessed],
//                messageCount: row[messageCount]
//            )
//            loadedSessions.append(session)
//        }
//        
//        DispatchQueue.main.async {
//            self.sessions = loadedSessions
//            self.currentSession = loadedSessions.first
//        }
//    }
//    
//    private func updateLastAccessed(sessionId: String) throws {
//        let update = sessionsTable
//            .filter(self.sessionId == sessionId)
//            .update(lastAccessed <- Date())
//        
//        try db.run(update)
//    }
//    
//    private func generateSessionId() -> String {
//        let timestamp = Date().timeIntervalSince1970
//        let randomComponent = UUID().uuidString.prefix(8)
//        return "session_\(Int(timestamp))_\(randomComponent)"
//    }
//    
//    // MARK: - Utility Methods
//    
//    func getSessionById(_ id: String) -> ChatSession? {
//        return sessions.first { $0.id == id }
//    }
//    
//    func getSessionsByLanguage(_ language: Language) -> [ChatSession] {
//        return sessions.filter { $0.language == language }
//    }
//    
//    func clearAllSessions() throws {
//        try db.run(sessionsTable.delete())
//        
//        DispatchQueue.main.async {
//            self.sessions.removeAll()
//            self.currentSession = nil
//        }
//    }
//}
//
//// MARK: - Session List View
//
//struct SessionListView: SwiftUICore.View {
//    @ObservedObject var sessionManager: SessionManager
//    var isPresented: Bool
//    let onSessionSelected: (ChatSession) -> Void
//    
//    @State private var showingNewSessionSheet = false
//    @State private var editingSession: ChatSession?
//    @State private var newSessionLanguage: Language = .english
//    
//    var body: some SwiftUICore.View {
//        NavigationView {
//            List {
//                // New Session Button
//                Button(action: {
//                    showingNewSessionSheet = true
//                }) {
//                    HStack {
//                        Image(systemName: "plus.circle.fill")
//                            .foregroundColor(.blue)
//                            .font(.title2)
//                        
//                        Text("New Chat")
//                            .font(.headline)
//                            .foregroundColor(.blue)
//                        
//                        Spacer()
//                    }
//                    .padding(.vertical, 8)
//                }
//                
//                // Sessions List
//                ForEach(sessionManager.sessions) { session in
//                    SessionRowView(
//                        session: session,
//                        isSelected: sessionManager.currentSession?.id == session.id,
//                        onTap: {
//                            try? sessionManager.switchToSession(session)
//                            onSessionSelected(session)
//                            isPresented = false
//                        },
//                        onEdit: {
//                            editingSession = session
//                        },
//                        onDelete: {
//                            try? sessionManager.deleteSession(session)
//                        }
//                    )
//                }
//            }
//            .navigationTitle("Chat Sessions")
//            .navigationBarItems(
//                leading: Button("Cancel") {
//                    isPresented = false
//                },
//                trailing: Menu {
//                    Button("Clear All Sessions") {
//                        try? sessionManager.clearAllSessions()
//                    }
//                    .foregroundColor(.red)
//                } label: {
//                    Image(systemName: "ellipsis.circle")
//                }
//            )
//        }
//        .sheet(isPresented: $showingNewSessionSheet) {
//            NewSessionView(
//                selectedLanguage: $newSessionLanguage,
//                onCreate: { language, title in
//                    if let newSession = try? sessionManager.createNewSession(language: language, title: title) {
//                        onSessionSelected(newSession)
//                        isPresented = false
//                    }
//                    showingNewSessionSheet = false
//                },
//                onCancel: {
//                    showingNewSessionSheet = false
//                }
//            )
//        }
//        .sheet(item: $editingSession) { session in
//            EditSessionView(
//                session: session,
//                onSave: { updatedTitle in
//                    try? sessionManager.updateSessionTitle(session, newTitle: updatedTitle)
//                    editingSession = nil
//                },
//                onCancel: {
//                    editingSession = nil
//                }
//            )
//        }
//    }
//}
//
//// MARK: - Session Row View
//
//struct SessionRowView: View {
//    let session: ChatSession
//    let isSelected: Bool
//    let onTap: () -> Void
//    let onEdit: () -> Void
//    let onDelete: () -> Void
//    
//    var body: some SwiftUICore.View {
//        Button(action: onTap) {
//            HStack {
//                VStack(alignment: .leading, spacing: 4) {
//                    HStack {
//                        Text(session.displayTitle)
//                            .font(.headline)
//                            .foregroundColor(.primary)
//                            .lineLimit(1)
//                        
//                        Spacer()
//                        
//                        Text(session.language.flag)
//                            .font(.title3)
//                    }
//                    
//                    HStack {
//                        Text("\(session.messageCount) messages")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                        
//                        Spacer()
//                        
//                        Text(session.formattedDate)
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
//                
//                if isSelected {
//                    Image(systemName: "checkmark.circle.fill")
//                        .foregroundColor(.blue)
//                        .font(.title2)
//                }
//            }
//            .padding(.vertical, 4)
//        }
//        .contextMenu {
//            Button("Edit Title") {
//                onEdit()
//            }
//            
//            Button("Delete", role: .destructive) {
//                onDelete()
//            }
//        }
//    }
//}
//
//// MARK: - New Session View
//
//struct NewSessionView: View {
//    @Binding var selectedLanguage: Language
//    let onCreate: (Language, String?) -> Void
//    let onCancel: () -> Void
//    
//    @State private var sessionTitle: String = ""
//    
//    var body: some View {
//        NavigationView {
//            VStack(spacing: 20) {
//                Text("Create New Chat Session")
//                    .font(.title2)
//                    .fontWeight(.semibold)
//                    .padding(.top)
//                
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("Language")
//                        .font(.headline)
//                    
//                    Picker("Language", selection: $selectedLanguage) {
//                        ForEach(Language.allCases, id: \.self) { language in
//                            HStack {
//                                Text(language.flag)
//                                Text(language.displayName)
//                            }
//                            .tag(language)
//                        }
//                    }
//                    .pickerStyle(SegmentedPickerStyle())
//                }
//                
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("Title (Optional)")
//                        .font(.headline)
//                    
//                    TextField(
//                        selectedLanguage == .english ? "Enter chat title..." : "Введите название чата...",
//                        text: $sessionTitle
//                    )
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                }
//                
//                Spacer()
//                
//                HStack(spacing: 20) {
//                    Button("Cancel") {
//                        onCancel()
//                    }
//                    .foregroundColor(.secondary)
//                    
//                    Button("Create") {
//                        let title = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
//                        onCreate(selectedLanguage, title.isEmpty ? nil : title)
//                    }
//                    .foregroundColor(.blue)
//                    .fontWeight(.semibold)
//                }
//                .padding(.bottom)
//            }
//            .padding()
//        }
//    }
//}
//
//// MARK: - Edit Session View
//
//struct EditSessionView: View {
//    let session: ChatSession
//    let onSave: (String) -> Void
//    let onCancel: () -> Void
//    
//    @State private var editedTitle: String
//    
//    init(session: ChatSession, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
//        self.session = session
//        self.onSave = onSave
//        self.onCancel = onCancel
//        self._editedTitle = State(initialValue: session.title)
//    }
//    
//    var body: some View {
//        NavigationView {
//            VStack(spacing: 20) {
//                Text("Edit Session Title")
//                    .font(.title2)
//                    .fontWeight(.semibold)
//                    .padding(.top)
//                
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("Session Title")
//                        .font(.headline)
//                    
//                    TextField(
//                        session.language == .english ? "Enter chat title..." : "Введите название чата...",
//                        text: $editedTitle
//                    )
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                }
//                
//                Spacer()
//                
//                HStack(spacing: 20) {
//                    Button("Cancel") {
//                        onCancel()
//                    }
//                    .foregroundColor(.secondary)
//                    
//                    Button("Save") {
//                        onSave(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines))
//                    }
//                    .foregroundColor(.blue)
//                    .fontWeight(.semibold)
//                }
//                .padding(.bottom)
//            }
//            .padding()
//        }
//    }
//}
//
//// MARK: - Session Management Integration
//
//extension BundledRAGView {
//    var sessionBasedCurrentSessionId: String {
//        return sessionManager.currentSession?.id ?? "default_session"
//    }
//    
//    func handleNewMessage() {
//        if let currentSession = sessionManager.currentSession {
//            try? sessionManager.updateMessageCount(currentSession, increment: 1)
//        }
//    }
//    
//    func switchToSession(_ session: ChatSession) async {
//        // Switch session in session manager
//        try? sessionManager.switchToSession(session)
//        
//        // Update language if different
//        if selectedLanguage != session.language {
//            selectedLanguage = session.language
//            setupSpeechRecognition()
//        }
//        
//        // Load chat history for this session
//        await loadChatHistory()
//    }
//}
