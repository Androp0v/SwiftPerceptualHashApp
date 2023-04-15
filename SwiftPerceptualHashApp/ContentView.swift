//
//  ContentView.swift
//  SwiftPerceptualHashApp
//
//  Created by Raúl Montón Pinillos on 12/4/23.
//

import Metal
import MetalKit
import SwiftPerceptualHash
import SwiftUI

struct ContentView: View {
    
    @State var image: Image?
    @State var hashes = [Hash]()
    struct Hash {
        let id = UUID()
        let text: String
    }
    let hashManager = try! PerceptualHashGenerator()
    let imageData = UIImage(named: "SampleImageFull.png")!.pngData()!
    
    var body: some View {
        HStack {
            ScrollView {
                LazyVStack {
                    ForEach(hashes, id: \.id) { hash in
                        Text(hash.text)
                    }
                }
            }
            Button("Do it!") {
                Task {
                    await doThing()
                }
            }
        }
        .padding()
    }
    
    func doThing() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    if let hash = try? await hashManager.perceptualHash(imageData: imageData) {
                        Task { @MainActor in
                            hashes.append(Hash(text: hash.stringValue))
                        }
                    }
                }
            }
        }
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("Time elapsed: \(timeElapsed) s.")
        // await doThing()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
