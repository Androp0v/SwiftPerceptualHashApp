//
//  ProcessImage.swift
//  SwiftPerceptualHashApp
//
//  Created by Raúl Montón Pinillos on 12/4/23.
//

import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import UIKit

func processImage() async throws -> CGImage? {
    // Get the image
    let image = UIImage(named: "SampleImageFull.png")
    
    // Get the image data
    guard let imageData = image?.pngData() else {
        print("Failed to get image data!")
        return nil
    }

    // Get Metal device
    guard let device = MTLCreateSystemDefaultDevice() else {
        print("Metal device creation failed!")
        return nil
    }

    // Get the default library
    guard let defaultLibrary = device.makeDefaultLibrary() else {
        print("Couldn't create default library!")
        return nil
    }

    // Create the grayscale kernel function
    guard let grayscaleKernel = defaultLibrary.makeFunction(name: "grayscale_kernel") else {
        print("Failed to create grayscale kernel!")
        return nil
    }

    // Create the grayscale Pipeline State Object
    let grayscalePSO = try await device.makeComputePipelineState(function: grayscaleKernel)

    // Create a texture loader
    let textureLoader = MTKTextureLoader(device: device)

    // Get texture from image
    let texture = try await textureLoader.newTexture(
        data: imageData,
        options: [
            MTKTextureLoader.Option.textureUsage: MTLTextureUsage.unknown.rawValue,
            MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue
        ]
    )
    
    // Create a 32x32 destination texture
    let resizedTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 32,
        height: 32,
        mipmapped: false
    )
    resizedTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    guard let resizedTexture = device.makeTexture(descriptor: resizedTextureDescriptor) else {
        print("Failed to create 32x32 destination texture.")
        return nil
    }

    // Create command queue
    guard let commandQueue = device.makeCommandQueue() else {
        print("Failed to create command queue!")
        return nil
    }

    // MARK: - Can be used more than once

    // Create command buffer
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
        print("Failed to create command buffer!")
        return nil
    }
    
    // Resize the image to target 32x32 resolution
    let resize = MPSImageBilinearScale(device: device)
    var transform = MPSScaleTransform(
        scaleX: 32.0 / Double(texture.width),
        scaleY: 32.0 / Double(texture.height),
        translateX: 0.0,
        translateY: 0.0
    )
    withUnsafePointer(to: &transform) { (transformPtr: UnsafePointer<MPSScaleTransform>) -> () in
        resize.scaleTransform = transformPtr
    }
    resize.encode(
        commandBuffer: commandBuffer,
        sourceTexture: texture,
        destinationTexture: resizedTexture
    )
    
    // Create compute command encoder
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
        print("Failed to create compute command encoder!")
        return nil
    }

    // Set the PSO to perform a grayscale conversion
    computeEncoder.setComputePipelineState(grayscalePSO)

    // Set the source texture
    computeEncoder.setTexture(resizedTexture, index: 0)

    // Dispatch the threads
    let threadgroupSize = MTLSizeMake(16, 16, 1)
    var threadgroupCount = MTLSize()
    threadgroupCount.width  = (resizedTexture.width + threadgroupSize.width - 1) / threadgroupSize.width
    threadgroupCount.height = (resizedTexture.height + threadgroupSize.height - 1) / threadgroupSize.height
    // The image data is 2D, so set depth to 1
    threadgroupCount.depth = 1
    computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)

    // Finish encoding
    computeEncoder.endEncoding()
    
    let cgImage = await withCheckedContinuation { continuation in
        commandBuffer.addCompletedHandler { _ in
            continuation.resume(returning: resizedTexture.getCGImage())
        }
        
        // Submit work to the GPU
        commandBuffer.commit()
    }
    return cgImage
}
