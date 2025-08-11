import CoreML
import Foundation
import MediaPipeTasksGenAI

//func initialise_llm()->LlmInference{
//    let modelPath = Bundle.main.path(forResource: "gemma-2b-it-cpu-int4",
//                                          ofType: "bin")!
func initializeLLM() throws -> LlmInference {
    guard let modelPath = Bundle.main.path(forResource: "gemma-2b-it-cpu-int4",
                                          ofType: "bin") else {
        throw NSError(domain: "ModelError", code: 1,
                     userInfo: [NSLocalizedDescriptionKey: "Model file not found"])
    }
    
    let options = LlmInference.Options(modelPath: modelPath)
    options.modelPath = modelPath
    options.maxTokens = 1000
    options.maxTopk = 40
    // options. = 0.8
    // options.randomSeed = 101
    
    let LlmInference = try LlmInference(options: options)
    return LlmInference
}

