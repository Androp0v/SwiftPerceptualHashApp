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
    
    var body: some View {
        VStack {
            if let image {
                image
            }
            Text("Hello, world!")
        }
        .padding()
        .task {
            let hashManager = try? PerceptualHashManager()
            guard let imageData = UIImage(named: "SampleImageFull.png")?.pngData() else {
                return
            }
            let hash = try? await hashManager?.perceptualHash(imageData: imageData)
            print(hash?.stringValue)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
