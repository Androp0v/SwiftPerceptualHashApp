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
    @State var hashes = [String: [Hash]]()
    
    struct Hash {
        let id = UUID()
        let url: URL
        let name: String
    }

    let sourceDirectory = try! FileManager.default.url(
        for: .downloadsDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    )
    let hashManager = try! PerceptualHashGenerator(resizedSize: 64, dctSize: 16)
    
    var body: some View {
        HStack {
            ScrollView(.vertical) {
                LazyVStack {
                    ForEach(hashes.filter({ $0.value.count > 1 }), id: \.key) { hash in
                        HStack {
                            Text(hash.key)
                            ScrollView(.horizontal) {
                                LazyHStack {
                                    HStack {
                                        ForEach(hash.value, id: \.id) { image in
                                            VStack {
                                                Image(uiImage: UIImage(data: try! Data(contentsOf: image.url))!)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                Text(image.name)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 256)
                    }
                }
            }
            Button("Do it!") {
                Task {
                    await doThing()
                }
            }
        }
    }
    
    func doThing() async {
        // Get a list of all files in the directory
        
        guard sourceDirectory.startAccessingSecurityScopedResource() else {
            return;
        }
        let directoryContents = FileManager.default.enumerator(at: sourceDirectory, includingPropertiesForKeys: nil)
        let filenames = directoryContents?.allObjects as! [URL]
        actor HashSync {
            var newHashes = [String: [Hash]]()
            func createOrAppend(hash: String, filename: URL) {
                print(hash)
                if newHashes[hash] != nil {
                    newHashes[hash]?.append(Hash(url: filename, name: filename.lastPathComponent))
                } else {
                    newHashes[hash] = [Hash(url: filename, name: filename.lastPathComponent)]
                }
            }
        }
        let hashActor = HashSync()
        await withTaskGroup(of: Void.self) { group in
            for filename in filenames[...10000] {
                guard filename.pathExtension == "png"
                        || filename.pathExtension == "jpg"
                        || filename.pathExtension == "PNG"
                        || filename.pathExtension == "JPG"
                else {
                    continue
                }
                group.addTask {
                    if let fileData = try? Data(contentsOf: filename) {
                        if let hash = try? await hashManager.perceptualHash(imageData: fileData) {
                            await hashActor.createOrAppend(hash: hash.stringValue, filename: filename)
                        }
                    }
                }
            }
        }
        hashes = await hashActor.newHashes
        /*
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
         */
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
