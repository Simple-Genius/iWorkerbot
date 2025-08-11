# ChatBot - AI-Powered iOS Chat Application

An iOS chat application that combines local AI language models with vector search capabilities to provide intelligent, context-aware conversations. The app uses Google's Gemma 2B model for text generation and DistilBERT for document embeddings and semantic search.

## Features

- **Local AI Processing**: Runs Google's Gemma 2B model locally on device using MediaPipe
- **Vector Search**: Semantic search through documents using DistilBERT embeddings
- **Document Processing**: Text chunking and embedding for knowledge base creation
- **SQLite Vector Store**: Optimized vector storage with cosine similarity search
- **Chat Persistence**: Session management and conversation history
- **iOS Native**: Built with SwiftUI for modern iOS devices

## Architecture

The app consists of several key components:

- **Language Model**: Gemma 2B quantized model (`gemma-2b-it-cpu-int4.bin`)
- **Embeddings**: DistilBERT model (`msmarco_distilbert_base_tas_b_512_single_quantized.mlpackage`)
- **Vector Database**: SQLite with custom vector operations
- **Text Processing**: Recursive character and token-based text splitters
- **Chat Interface**: SwiftUI-based conversation UI

## Setup Instructions

### Prerequisites

- Xcode 15.0 or later
- iOS 15.0 or later target device/simulator
- CocoaPods for dependency management

### Dependencies

The project uses the following key dependencies:

- **MediaPipeTasksGenAI**: Google's MediaPipe framework for on-device AI
- **SQLite.swift**: Swift wrapper for SQLite database operations

### Installation Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/Simple-Genius/iWorkerbot
   cd ChatBot
   ```

2. **Install CocoaPods dependencies**
   ```bash
   pod install
   ```

3. **Open the workspace in Xcode**
   ```bash
   open ChatBot.xcworkspace
   ```

4. **Obtain required model files** (see Large Files section below)

5. **Build and run**
   - Select your target device or simulator
   - Build and run the project in Xcode

## Running the Application

1. Launch the app on your iOS device or simulator
2. The app will initialize the AI models on first run
3. Start chatting with the AI assistant
4. Upload documents to create a searchable knowledge base
5. The AI will use both its training data and your documents to provide relevant responses

## Large Model Files

Due to Git's file size limitations, the following large files are excluded from the repository:

### Required Files (obtain separately):

- `gemma-2b-it-cpu-int4.bin` (~1.5GB) - Quantized Gemma 2B model
- `msmarco_distilbert_base_tas_b_512_single_quantized.mlpackage/` - DistilBERT embeddings model
- Various `.txt` files containing knowledge base documents

### How to obtain model files:

1. **Gemma Model**: Download from Google AI or Hugging Face
2. **DistilBERT Model**: Available from Hugging Face or convert from PyTorch
3. Place the files in the `ChatBot/` directory as shown in the project structure

## Project Structure

```
ChatBot/
├── ChatBotApp.swift              # Main app entry point
├── gemma_mediapipeApp.swift      # Alternative app entry point
├── VectorDataBase.swift          # SQLite vector store implementation
├── DistillbertEmbeddings.swift   # Embeddings generation
├── ChatPersistence.swift         # Chat session management
├── SessionManager.swift          # Session handling
├── RecursiveCharacterTextSplitter.swift  # Text chunking
├── BertTokenizer.swift           # Tokenization utilities
├── Assets.xcassets/              # App icons and assets
├── gemma-2b-it-cpu-int4.bin     # Language model (excluded)
├── msmarco_distilbert_base_tas_b_512_single_quantized.mlpackage/ # Embeddings model
└── *.txt                        # Knowledge base documents
```

## Key Components

### Vector Database (`VectorDataBase.swift`)
- SQLite-based vector storage with optimized similarity search
- Support for batch operations and metadata filtering
- Configurable for different embedding dimensions

### Embeddings (`DistillbertEmbeddings.swift`)
- DistilBERT-based text embeddings
- Optimized for semantic similarity
- Supports batch processing

### Text Processing
- Recursive character-based text splitting
- Token-aware chunking for optimal embedding
- Configurable chunk sizes and overlap

## Development Notes

- The app is designed to run entirely on-device for privacy
- Large model files are loaded into memory - ensure sufficient device RAM
- Vector operations use Apple's Accelerate framework for performance
- Database operations are thread-safe with concurrent queues

## Troubleshooting

1. **Out of Memory**: Reduce model size or use device with more RAM
2. **Slow Performance**: Check if running on simulator vs device
3. **Model Loading Errors**: Verify model files are correctly placed
4. **Build Errors**: Ensure all CocoaPods dependencies are installed
