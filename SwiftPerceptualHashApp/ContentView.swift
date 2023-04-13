//
//  ContentView.swift
//  SwiftPerceptualHashApp
//
//  Created by Raúl Montón Pinillos on 12/4/23.
//

import Metal
import MetalKit
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
            print(try? await PerceptualHash()?.perceptualHash())
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
