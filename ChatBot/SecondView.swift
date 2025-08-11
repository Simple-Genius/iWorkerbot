//
//  Language.swift
//  ChatBot
//
//  Created by Ajila Ibrahim Adeboye on 8/5/25.
//


import SwiftUI
import CoreML
import MediaPipeTasksGenAI
import Speech
import AVFoundation

enum Language: String, CaseIterable {
    case english = "en"
    case russian = "ru"
    
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .russian: return "🇷🇺"
        }
    }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Russian"
        }
    }
    
    var documentId: String {
        switch self {
        case .english: return "knowledge_base_english_v1"
        case .russian: return "knowledge_base_russian_v1"
        }
    }
    
    var fileName: String {
        switch self {
        case .english: return "uk_seasonal_worker_knowledge"
        case .russian: return "UK_Seasonal_Worker_Russian"
        }
    }
    
    var welcomeMessage: String {
        switch self {
        case .english: return "Welcome to WorkerBot! Ask me anything about UK seasonal work."
        case .russian: return "Добро пожаловать в WorkerBot! Спросите меня о сезонной работе в Великобритании."
        }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    var text: String
    let isUser: Bool
    let timestamp = Date()
    var isStreaming: Bool = false
}

struct BundledRAGView: View {
    @State private var selectedLanguage: Language = .english
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isInitialized = false
    @State private var isProcessing = false
    @State private var initializationError: String?
    @State private var isGeneratingResponse = false
    @State private var loadingStage: LoadingStage = .initializing
    @State private var currentProcessingLanguage: Language?
    
    enum LoadingStage: CaseIterable {
        case initializing
        case loadingLLM
        case loadingEmbeddings
        case loadingVectorStore
        case processingEnglishKnowledge
        case processingRussianKnowledge
        case complete
        
//        func description(for language: Language) -> String {
//            switch self {
//            case .initializing:
//                return language == .english ? "Starting up..." : "Запуск..."
//            case .loadingLLM:
//                return language == .english ? "Loading AI model..." : "Загрузка модели ИИ..."
//            case .loadingEmbeddings:
//                return language == .english ? "Loading embeddings..." : "Загрузка векторных представлений..."
//            case .loadingVectorStore:
//                return language == .english ? "Setting up vector database..." : "Настройка векторной базы данных..."
//            case .processingEnglishKnowledge:
//                return language == .english ? "Processing English knowledge base..." : "Обработка английской базы знаний..."
//            case .processingRussianKnowledge:
//                return language == .english ? "Processing Russian knowledge base..." : "Обработка русской базы знаний..."
//            case .complete:
//                return language == .english ? "Ready!" : "Готово!"
//            }
//        }
    }
    
    // Core components
    @State private var llmModel: LlmInference?
    @State private var vectorStore: SQLiteVectorStore?
    @State private var embeddingModel: DistilbertEmbeddings?
    @State private var chatManager: ChatPersistenceManager?
    
    // Speech Recognition States
    @State private var speechRecognizer: SFSpeechRecognizer?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    @State private var isRecording = false
    @State private var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var hasRequestedAuthorization = false
    
    private var currentSessionId: String {
        "chat_session_\(selectedLanguage.rawValue)"
    }
    
    var body: some View {
        ZStack {
            // Main Chat Interface
            VStack(spacing: 0) {
                // Header with bright gradient background
                VStack(spacing: 12) {
                    HStack {
                        Text("WorkerBot")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Language Picker - disabled during initialization
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(Language.allCases, id: \.self) { language in
                                Text(language.flag)
                                    .font(.title2)
                                    .tag(language)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 120)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                        .disabled(!isInitialized || isProcessing)
                        .onChange(of: selectedLanguage) {
                            if isInitialized {
                                Task { await switchLanguage() }
                            }
                        }
//                        .onChange(of: selectedLanguage) { _ in
//                            if isInitialized {
//                                Task { await switchLanguage() }
//                            }
//                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .padding(.bottom, 20)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.purple, .blue, .cyan]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Error display with bright styling
                if let error = initializationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text(error)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                
                // Chat Messages with bright background
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            SimpleMessageBubble(message: message)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .rotationEffect(.degrees(180))
                }
                .rotationEffect(.degrees(180))
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.cyan.opacity(0.1), Color.purple.opacity(0.1)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Input Area - Fixed
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    HStack(spacing: 12) {
                        TextField(
                            selectedLanguage == .english ? "Ask a question..." : "Задайте вопрос...",
                            text: $messageText
                        ).foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(25)
                        .shadow(color: .gray.opacity(0.2), radius: 3, x: 0, y: 1)
                        .disabled(!isInitialized || isProcessing || isGeneratingResponse)
                        .onSubmit { sendMessage() }
                        
                        // Speech Recognition Button
                        Button(action: toggleRecording) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: isRecording ? [.red, .orange] : [.gray, .gray.opacity(0.7)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                if isRecording {
                                    // Recording animation
                                    Circle()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                        .scaleEffect(isRecording ? 1.2 : 1.0)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                                }
                                
                                Image(systemName: isRecording ? "mic.fill" : "mic")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                        .disabled(!isInitialized || isProcessing || isGeneratingResponse)
                        .shadow(color: isRecording ? .red.opacity(0.3) : .gray.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        // Send Button
                        Button(action: sendMessage) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: isInitialized && !messageText.isEmpty ? [.blue, .purple] : [.gray.opacity(0.5)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                if isGeneratingResponse {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 18, weight: .semibold))
                                }
                            }
                        }
                        .disabled(!isInitialized || messageText.isEmpty || isProcessing || isGeneratingResponse)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color.white)
            }
            .onAppear {
                setupSpeechRecognition()
                Task {
              
                    await initialize()
                    
//                    if isInitialized {
//                              await processBatchQuestions() // <- This processes all 150 questions
//                          }
                }
            }
            
            // Loading Overlay
            if !isInitialized && initializationError == nil {
                LoadingOverlay(
                    selectedLanguage: selectedLanguage,
                    loadingStage: loadingStage,
                    currentProcessingLanguage: currentProcessingLanguage
                )
            }
            
            // Error Overlay
            if let error = initializationError {
                ErrorOverlay(error: error) {
                    // Retry action
                    initializationError = nil
                    Task {
                        await initialize()
                    }
                }
            }
        }
    }
    
    // MARK: - Speech Recognition Setup
    
    private func setupSpeechRecognition() {
        // Initialize speech recognizer with current language
        let locale = Locale(identifier: selectedLanguage.rawValue == "en" ? "en-US" : "ru-RU")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        
      //  // print("Speech recognizer setup for \(locale.identifier)")
        // print("Authorization status: \(speechAuthorizationStatus.rawValue)")
    }
    
    // MARK: - Speech Recognition Methods
    
    private func toggleRecording() {
        //// print("Toggle recording tapped. Current state: \(isRecording)")
        
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
       // // print("Starting recording...")
        
        // Check if we need to request authorization
        if speechAuthorizationStatus == .notDetermined && !hasRequestedAuthorization {
           // // print("Requesting speech authorization...")
            requestSpeechAuthorization()
            return
        }
        
        // Check if we have authorization
        guard speechAuthorizationStatus == .authorized else {
            //  // print("Speech recognition not authorized. Status: \(speechAuthorizationStatus.rawValue)")
            return
        }
        
        // Start recording
        do {
            try startSpeechRecognition()
        } catch {
            // // print("Failed to start speech recognition: \(error)")
        }
    }
    
    private func requestSpeechAuthorization() {
        hasRequestedAuthorization = true
        
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                self.speechAuthorizationStatus = authStatus
                //  // print("Speech authorization result: \(authStatus.rawValue)")
                
//                switch authStatus {
//                case .authorized:
//                    //   // print("Speech recognition authorized")
//                    // Auto-start recording after authorization
//                    self.startRecording()
//                case .denied:
//                    //  // print("Speech recognition authorization denied")
//                case .restricted:
//                    //  // print("Speech recognition restricted on this device")
//                case .notDetermined:
//                    //  // print("Speech recognition authorization not determined")
//                @unknown default:
//                     // print("Unknown speech recognition authorization status")
//                }
            }
        }
    }
    
    private func startSpeechRecognition() throws {
        //  // print("Actually starting speech recognition...")
        
        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Get input node
        let inputNode = audioEngine.inputNode
        
        // Create recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            DispatchQueue.main.async {
                if let result = result {
                   // // print("Speech recognition result: \(result.bestTranscription.formattedString)")
                    // Update text field with transcribed text
                    self.messageText = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        //  // print("Speech recognition final result")
                        self.stopRecording()
                    }
                }
                
                if let error = error {
                    //  // print("Speech recognition error: \(error)")
                    self.stopRecording()
                }
            }
        }
        
        // Configure audio format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        //  // print("Speech recognition started successfully")
    }
    
    private func stopRecording() {
        //   // print("Stopping recording...")
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        //  // print("Recording stopped")
    }
    
    // MARK: - Chat Functions
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        //  // print("Sending message: \(messageText)")
        
        let userMessage = messageText
        let query = "[USER]" + userMessage
        
        // Add user message to chat
        messages.append(ChatMessage(text: userMessage, isUser: true))
        
        // Save to chat manager
        chatManager?.saveMessage(sessionId: currentSessionId, message: query, isUser: true)
        
        // Clear the text field
        messageText = ""
        
        // Generate response
        Task {
            await generateStreamingResponse(for: userMessage)
        }
    }
    
    // MARK: - Initialization
    
    @MainActor
    func initialize() async {
        do {
            loadingStage = .loadingVectorStore
            self.vectorStore = try SQLiteVectorStore()
            
            loadingStage = .loadingEmbeddings
            self.chatManager = try ChatPersistenceManager()
            self.embeddingModel = DistilbertEmbeddings()
            
            loadingStage = .loadingLLM
            self.llmModel = try initializeLLM()

            await loadChatHistory()
            
            let shouldProcessKnowledgeBases = await checkIfInitialProcessingNeeded()
            if shouldProcessKnowledgeBases {
                await processAllKnowledgeBases()
            } else {
                // print("Knowledge bases already processed, skipping initialization...")
            }
            
            loadingStage = .complete
            
            // Small delay to show "Ready!" state
            try await Task.sleep(nanoseconds: 500_000_000)
            isInitialized = true
            
        } catch {
            initializationError = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    @MainActor
    func checkIfInitialProcessingNeeded() async -> Bool {
        // Check if BOTH knowledge bases have been processed
        let englishProcessed = UserDefaults.standard.bool(forKey: "kb_processed_\(Language.english.documentId)")
        let russianProcessed = UserDefaults.standard.bool(forKey: "kb_processed_\(Language.russian.documentId)")
        
        // Only process if either one is missing
        let needsProcessing = !englishProcessed || !russianProcessed
        
        if !needsProcessing {
            // Double-check with database to ensure data actually exists
            let englishExists = await checkKnowledgeBaseExists(for: .english)
            let russianExists = await checkKnowledgeBaseExists(for: .russian)
            
            return !englishExists || !russianExists
        }
        
        return needsProcessing
    }
    
    @MainActor
    func processAllKnowledgeBases() async {
        // Check and process English knowledge base
        loadingStage = .processingEnglishKnowledge
        currentProcessingLanguage = .english
        
        let englishExists = await checkKnowledgeBaseExists(for: .english)
        if !englishExists {
            await processKnowledgeBase(for: .english)
        } else {
        }
        
        // Check and process Russian knowledge base
        loadingStage = .processingRussianKnowledge
        currentProcessingLanguage = .russian
        
        let russianExists = await checkKnowledgeBaseExists(for: .russian)
        if !russianExists {
            //  // print("Processing Russian knowledge base...")
            await processKnowledgeBase(for: .russian)
        } else {
            //  // print("Russian knowledge base already exists, skipping...")
        }
        
        currentProcessingLanguage = nil
    }
    
    @MainActor
    func loadChatHistory() async {
        let savedMessages = chatManager?.loadMessages(for: currentSessionId) ?? []
        let stringMessages = savedMessages.isEmpty ? [selectedLanguage.welcomeMessage] : savedMessages
        
        messages = stringMessages.map { msg in
            ChatMessage(text: msg.replacingOccurrences(of: "[USER]", with: ""),
                       isUser: msg.contains("[USER]"))
        }
    }
    
    @MainActor
    func switchLanguage() async {
        // Clear current messages
        messages.removeAll()
        
        // Load saved messages for new language
        await loadChatHistory()
        
        // Update speech recognition for new language
        setupSpeechRecognition()
    }
    
    func checkKnowledgeBaseExists(for language: Language) async -> Bool {
        guard let store = vectorStore else { return false }
        
        do {
            let stats = try store.getDocumentStats()
            let exists = stats.contains { $0.documentId == language.documentId }
            // // print("Knowledge base exists for \(language.documentId): \(exists)")
            return exists
        } catch {
            //  // print("Error checking knowledge base: \(error)")
            return false
        }
    }
    
    @MainActor
    func processKnowledgeBase(for language: Language) async {
        do {
            guard let docURL = Bundle.main.url(forResource: language.fileName,
                                             withExtension: "txt") else {
                throw NSError(domain: "LanguageRAG", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "\(language.displayName) knowledge base file not found"])
            }
            
            // print("Processing knowledge base for \(language.documentId)")
            
            let content = try String(contentsOf: docURL, encoding: .utf8)
            let splitter = RecursiveTokenSplitter(withTokenizer: BertTokenizer())
            let (chunks, _) = splitter.split(text: content, chunkSize: 100, overlapSize: 20)
            
            // print("Split \(language.displayName) content into \(chunks.count) chunks")
            
            var batchData: [(index: Int, text: String, embedding: [Float])] = []
            
            for (index, chunk) in chunks.enumerated() {
                autoreleasepool {
                    if let embedding = embeddingModel?.encode(sentence: chunk) {
                        batchData.append((index: index, text: chunk, embedding: embedding))
                        
                        if batchData.count >= 10 {
                            try? vectorStore?.addVectorsBatch(
                                documentId: language.documentId,
                                chunks: batchData
                            )
                            batchData.removeAll()
                        }
                    }
                }
            }
            
            if !batchData.isEmpty {
                try vectorStore?.addVectorsBatch(
                    documentId: language.documentId,
                    chunks: batchData
                )
            }
            
            //  // print("Successfully processed \(language.displayName) knowledge base")
            
            // Save processing completion flag
            UserDefaults.standard.set(true, forKey: "processed_\(language.documentId)")
            
        } catch {
            // // print("Error processing \(language.displayName) knowledge base: \(error)")
        }
    }
    
    @MainActor
    func generateStreamingResponse(for query: String) async {
        guard let model = llmModel,
              let vectorStore = vectorStore,
              let embeddingModel = embeddingModel else {
            return
        }
        
        isGeneratingResponse = true
        
        let botMessage = ChatMessage(text: "", isUser: false, isStreaming: true)
        messages.append(botMessage)
        let messageIndex = messages.count - 1
        
        do {
            guard let queryEmbedding = embeddingModel.encode(sentence: query) else {
                updateStreamingMessage(at: messageIndex, with: "Failed to process your question.", isComplete: true)
                return
            }
            
            let searchResults = try vectorStore.search(
                queryEmbedding: queryEmbedding,
                topK: 5,
                documentId: selectedLanguage.documentId
            )
            
            let context = searchResults.map { $0.chunkText }.joined(separator: "\n\n")
            
            let prompt: String
            if selectedLanguage == .english {
                prompt = """
                Based on the following information, answer the user's question in English.
                
                Context:
                \(context)
                
                Question: \(query)
                
                Answer:
                """
            } else {
                prompt = """
                На основе следующей информации ответьте на вопрос пользователя на русском языке.
                
                Контекст:
                \(context)
                
                Вопрос: \(query)
                
                Ответ:
                """
            }
            
            try await streamResponse(model: model, prompt: prompt, messageIndex: messageIndex)
            
        } catch {
            let errorMsg = "Error: \(error.localizedDescription)"
            updateStreamingMessage(at: messageIndex, with: errorMsg, isComplete: true)
        }
        
        isGeneratingResponse = false
    }
    
    @MainActor
    private func streamResponse(model: LlmInference, prompt: String, messageIndex: Int) async throws {
        var accumulatedText = ""
        
        if let streamingModel = model as? StreamingLlmInference {
            try await streamingModel.generateResponseStream(inputText: prompt) { partialResponse in
                Task { @MainActor in
                    accumulatedText += partialResponse
                    self.updateStreamingMessage(at: messageIndex, with: accumulatedText, isComplete: false)
                }
            }
        } else {
            let fullResponse = try model.generateResponse(inputText: prompt)
            await simulateStreaming(response: fullResponse, messageIndex: messageIndex)
        }
        
        updateStreamingMessage(at: messageIndex, with: accumulatedText.isEmpty ? try model.generateResponse(inputText: prompt) : accumulatedText, isComplete: true)
        
        let finalText = messages[messageIndex].text
        chatManager?.saveMessage(sessionId: currentSessionId, message: finalText, isUser: false)
    }
    
    @MainActor
    private func simulateStreaming(response: String, messageIndex: Int) async {
        let words = response.components(separatedBy: " ")
        var accumulatedText = ""
        
        for (index, word) in words.enumerated() {
            accumulatedText += (index == 0 ? "" : " ") + word
            updateStreamingMessage(at: messageIndex, with: accumulatedText, isComplete: false)
            
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    
    @MainActor
    private func updateStreamingMessage(at index: Int, with text: String, isComplete: Bool) {
        guard index < messages.count else { return }
        
        messages[index].text = text
        messages[index].isStreaming = !isComplete
    }
}

// MARK: - Loading Overlay (Updated)
struct LoadingOverlay: View {
    let selectedLanguage: Language
    let loadingStage: BundledRAGView.LoadingStage
    let currentProcessingLanguage: Language?
    @State private var animationOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            // Background with gradient
            LinearGradient(
                gradient: Gradient(colors: [.purple.opacity(0.95), .blue.opacity(0.95), .cyan.opacity(0.95)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // App Logo/Icon Area
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulseScale)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(rotationAngle))
                        .animation(.linear(duration: 3.0).repeatForever(autoreverses: false), value: rotationAngle)
                }
                .onAppear {
                    pulseScale = 1.2
                    rotationAngle = 360
                }
                
                Spacer()
                // App Title
                VStack(spacing: 8) {
                    Text("WorkerBot")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(selectedLanguage == .english ? 
                         "AI Assistant for Seasonal Workers" : 
                         "ИИ Помощник для Сезонных Работников")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                
                // Loading Animation and Progress
                VStack(spacing: 20) {
                    // Progress indicator
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        
//                        // Current loading stage
//                        Text(loadingStage.description(for: selectedLanguage))
//                            .font(.system(size: 18, weight: .medium))
//                            .foregroundColor(.white)
//                            .multilineTextAlignment(.center)
                        
                        // Show which language is being processed
                        if let processingLang = currentProcessingLanguage {
                            Text("(\(processingLang.flag) \(processingLang.displayName))")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
//                   d
                    
                    // Progress steps
                    VStack(spacing: 8) {
                        LoadingProgressSteps(currentStage: loadingStage, language: selectedLanguage)
                    }
                    .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Tip text
                Text(selectedLanguage == .english ?
                     "💡 Preparing both English and Russian chats" :
                     "💡 Подготавливаем чаты на английском и русском языках")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
            .padding(.top, 100)
        }
    }
}

// MARK: - Loading Progress Steps (Updated)
struct LoadingProgressSteps: View {
    let currentStage: BundledRAGView.LoadingStage
    let language: Language
    
    private let allStages: [BundledRAGView.LoadingStage] = [
        .initializing, 
        .loadingVectorStore, 
        .loadingEmbeddings, 
        .loadingLLM, 
        .processingEnglishKnowledge,
        .processingRussianKnowledge,
        .complete
    ]
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(allStages.enumerated()), id: \.offset) { index, stage in
                HStack {
                    // Step indicator
//                    Circle()
//                        .fill(getStepColor(for: stage))
//                        .frame(width: 12, height: 12)
                    
                    // Step description
//                    Text(getStepDescription(for: stage))
//                        .font(.system(size: 12))
//                        .foregroundColor(getTextColor(for: stage))
//                    
//                    Spacer()
                    
                    // Show language flag for knowledge base steps
//                    if stage == .processingEnglishKnowledge {
//                        Text("🇬🇧")
//                            .font(.system(size: 12))
//                    } else if stage == .processingRussianKnowledge {
//                        Text("🇷🇺")
//                            .font(.system(size: 12))
//                    }
                }
            }
        }
    }
    
    private func getStepColor(for stage: BundledRAGView.LoadingStage) -> Color {
        let currentIndex = allStages.firstIndex(of: currentStage) ?? 0
        let stageIndex = allStages.firstIndex(of: stage) ?? 0
        
        if stageIndex < currentIndex {
            return .green  // Completed
        } else if stageIndex == currentIndex {
            return .yellow  // Current
        } else {
            return .white.opacity(0.3)  // Pending
        }
    }
    
    private func getTextColor(for stage: BundledRAGView.LoadingStage) -> Color {
        let currentIndex = allStages.firstIndex(of: currentStage) ?? 0
        let stageIndex = allStages.firstIndex(of: stage) ?? 0
        
        if stageIndex <= currentIndex {
            return .white
        } else {
            return .white.opacity(0.5)
        }
    }
    
    private func getStepDescription(for stage: BundledRAGView.LoadingStage) -> String {
        switch stage {
        case .initializing:
            return language == .english ? "Starting application" : "Запуск приложения"
        case .loadingVectorStore:
            return language == .english ? "Vector database" : "Векторная база данных"
        case .loadingEmbeddings:
            return language == .english ? "Text embeddings" : "Текстовые векторы"
        case .loadingLLM:
            return language == .english ? "AI language model" : "Языковая модель ИИ"
        case .processingEnglishKnowledge:
            return language == .english ? "English knowledge" : "Английские знания"
        case .processingRussianKnowledge:
            return language == .english ? "Russian knowledge" : "Русские знания"
        case .complete:
            return language == .english ? "Ready to chat!" : "Готов к общению!"
        }
    }
}

// MARK: - Simple Message Bubble
struct SimpleMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 50) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(message.text)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(message.isUser ? Color.purple : Color.white)
                        .foregroundColor(message.isUser ? .white : .black)
                        .cornerRadius(18)
                        .shadow(color: .gray.opacity(0.2), radius: 3, x: 0, y: 2)
                        .textSelection(.enabled)
                    
                    if message.isStreaming && !message.isUser {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                            .scaleEffect(0.6)
                    }
                }
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .opacity(0.7)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            if !message.isUser { Spacer(minLength: 50) }
        }
    }
}

// MARK: - Error Overlay
struct ErrorOverlay: View {
    let error: String
    let retryAction: () -> Void
    
    var body: some View {
        ZStack {
            Color.red.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Error icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                
                // Error message
                VStack(spacing: 12) {
                    Text("Initialization Error")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(error)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Retry button
                Button(action: retryAction) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(25)
                }
                
                Spacer()
            }
            .padding(.top, 100)
        }
    }
}

// MARK: - Streaming Protocol
protocol StreamingLlmInference {
    func generateResponseStream(inputText: String, onPartialResponse: @escaping (String) -> Void) async throws
}

// MARK: - ContentView
struct ContentView: View {
   @State private var chatManager: ChatPersistenceManager?
   @State private var selectedLanguage: Language = .english
   
   var body: some View {
       NavigationView {
           BundledRAGView()
               .navigationBarHidden(true)
               .navigationBarItems(trailing:
                   Menu {
                       Button(action: {
                           chatManager?.clearHistory(for: "chat_session_\(selectedLanguage.rawValue)")
                           // print("Chat history cleared")
                       }) {
                           Label("Clear Chat History", systemImage: "trash")
                       }
                       
                       Button(action: {
                           // Show app info
                       }) {
                           Label("About", systemImage: "info.circle")
                       }
                   } label: {
                       Image(systemName: "ellipsis.circle.fill")
                           .foregroundColor(.white)
                           .font(.title2)
                   }
               )
       }
       .navigationViewStyle(StackNavigationViewStyle())
   }
}

// Add this extension to your Language.swift file

//extension BundledRAGView {
//    
//    // MARK: - Batch Processing Functions
//    
//    struct QuestionResponse {
//        let question: String
//        let response: String
//        let language: Language
//        let timestamp: Date
//    }
//    
//    @MainActor
//    func processBatchQuestions() async {
//        guard isInitialized else {
//            print("❌ System not initialized yet")
//            return
//        }
//        
//        print("🚀 Starting batch processing of questions...")
//        
//        // Load questions from files
//        let englishQuestions = loadQuestionsFromFile(language: .english)
//        let russianQuestions = loadQuestionsFromFile(language: .russian)
//        
//        var allResponses: [QuestionResponse] = []
//        
//        // Process English questions
//        print("📝 Processing \(englishQuestions.count) English questions...")
//        for (index, question) in englishQuestions.enumerated() {
//            print("🔄 English \(index + 1)/\(englishQuestions.count): \(question.prefix(50))...")
//            
//            selectedLanguage = .english
//            let response = await generateBatchResponse(for: question)
//            
//            allResponses.append(QuestionResponse(
//                question: question,
//                response: response,
//                language: .english,
//                timestamp: Date()
//            ))
//            
//            // Small delay to prevent overwhelming the system
//            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
//        }
//        
//        // Process Russian questions
//        print("📝 Processing \(russianQuestions.count) Russian questions...")
//        for (index, question) in russianQuestions.enumerated() {
//            print("🔄 Russian \(index + 1)/\(russianQuestions.count): \(question.prefix(50))...")
//            
//            selectedLanguage = .russian
//            let response = await generateBatchResponse(for: question)
//            
//            allResponses.append(QuestionResponse(
//                question: question,
//                response: response,
//                language: .russian,
//                timestamp: Date()
//            ))
//            
//            // Small delay to prevent overwhelming the system
//            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
//        }
//        
//        // Save all responses
//        await saveBatchResponses(allResponses)
//        
//        print("✅ Batch processing complete! Generated \(allResponses.count) responses")
//    }
//    
//    private func loadQuestionsFromFile(language: Language) -> [String] {
//        let fileName = language == .english ? "paste-2" : "paste-3"
//        
//        guard let url = Bundle.main.url(forResource: fileName, withExtension: "txt"),
//              let content = try? String(contentsOf: url, encoding: .utf8) else {
//            print("❌ Could not load questions file for \(language.displayName)")
//            return []
//        }
//        
//        // Split by lines and filter out empty lines and headers
//        let lines = content.components(separatedBy: .newlines)
//            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
//            .filter { !$0.isEmpty && $0 != "Question" && $0 != "Вопрос" }
//        
//        print("✅ Loaded \(lines.count) questions for \(language.displayName)")
//        return lines
//    }
//    
//    private func generateBatchResponse(for question: String) async -> String {
//        guard let model = llmModel,
//              let vectorStore = vectorStore,
//              let embeddingModel = embeddingModel else {
//            return "Error: System components not available"
//        }
//        
//        do {
//            // Get query embedding
//            guard let queryEmbedding = embeddingModel.encode(sentence: question) else {
//                return "Error: Failed to process question"
//            }
//            
//            // Search for relevant context
//            let searchResults = try vectorStore.search(
//                queryEmbedding: queryEmbedding,
//                topK: 5,
//                documentId: selectedLanguage.documentId
//            )
//            
//            let context = searchResults.map { $0.chunkText }.joined(separator: "\n\n")
//            
//            // Create prompt
//            let prompt: String
//            if selectedLanguage == .english {
//                prompt = """
//                Based on the following information, answer the user's question in English. Provide a clear, helpful response.
//                
//                Context:
//                \(context)
//                
//                Question: \(question)
//                
//                Answer:
//                """
//            } else {
//                prompt = """
//                На основе следующей информации ответьте на вопрос пользователя на русском языке. Предоставьте четкий и полезный ответ.
//                
//                Контекст:
//                \(context)
//                
//                Вопрос: \(question)
//                
//                Ответ:
//                """
//            }
//            
//            // Generate response
//            let response = try model.generateResponse(inputText: prompt)
//            return response
//            
//        } catch {
//            return "Error: \(error.localizedDescription)"
//        }
//    }
//    
//    private func saveBatchResponses(_ responses: [QuestionResponse]) async {
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
//        let timestamp = dateFormatter.string(from: Date())
//        
//        // Create output text
//        var output = "# Batch Q&A Processing Results\n"
//        output += "Generated on: \(Date())\n"
//        output += "Total responses: \(responses.count)\n\n"
//        
//        // Group by language
//        let englishResponses = responses.filter { $0.language == .english }
//        let russianResponses = responses.filter { $0.language == .russian }
//        
//        // English section
//        output += "## English Questions & Answers (\(englishResponses.count))\n\n"
//        for (index, response) in englishResponses.enumerated() {
//            output += "### Question \(index + 1)\n"
//            output += "**Q:** \(response.question)\n\n"
//            output += "**A:** \(response.response)\n\n"
//            output += "---\n\n"
//        }
//        
//        // Russian section
//        output += "## Russian Questions & Answers (\(russianResponses.count))\n\n"
//        for (index, response) in russianResponses.enumerated() {
//            output += "### Вопрос \(index + 1)\n"
//            output += "**В:** \(response.question)\n\n"
//            output += "**О:** \(response.response)\n\n"
//            output += "---\n\n"
//        }
//        
//        // Save to Documents directory
//        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
//            let fileURL = documentsDirectory.appendingPathComponent("batch_qa_results_\(timestamp).txt")
//            
//            do {
//                try output.write(to: fileURL, atomically: true, encoding: .utf8)
//                print("✅ Results saved to: \(fileURL.path)")
//                
//                // Also save as JSON for programmatic access
//                await saveBatchResponsesAsJSON(responses, timestamp: timestamp)
//                
//            } catch {
//                print("❌ Failed to save results: \(error)")
//            }
//        }
//    }
//    
//    private func saveBatchResponsesAsJSON(_ responses: [QuestionResponse], timestamp: String) async {
//        let jsonResponses = responses.map { response in
//            [
//                "question": response.question,
//                "response": response.response,
//                "language": response.language.rawValue,
//                "timestamp": ISO8601DateFormatter().string(from: response.timestamp)
//            ]
//        }
//        
//        do {
//            let jsonData = try JSONSerialization.data(withJSONObject: jsonResponses, options: .prettyPrinted)
//            
//            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
//                let fileURL = documentsDirectory.appendingPathComponent("batch_qa_results_\(timestamp).json")
//                try jsonData.write(to: fileURL)
//                print("✅ JSON results saved to: \(fileURL.path)")
//            }
//        } catch {
//            print("❌ Failed to save JSON results: \(error)")
//        }
//    }
//}
