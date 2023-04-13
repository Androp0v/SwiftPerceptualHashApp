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

class PerceptualHash {
    
    let resizedSize: Int = 32
    let dctSize: Int = 8
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let grayscalePSO: MTLComputePipelineState
    
    let texture: MTLTexture
    let resizedTexture: MTLTexture
    let grayscaleTexture: MTLTexture
    
    // MARK: - Initialization
    
    init?() {
        // Get the image
        let image = UIImage(named: "SampleImageFullMod.png")
        
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
        self.device = device
        
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
        guard let grayscalePSO = try? device.makeComputePipelineState(function: grayscaleKernel) else {
            print("Failed to create grayscale pipeline!")
            return nil
        }
        self.grayscalePSO = grayscalePSO
        
        // Create a texture loader
        let textureLoader = MTKTextureLoader(device: device)
        
        // Get texture from image
        guard let texture = try? textureLoader.newTexture(
            data: imageData,
            options: [
                MTKTextureLoader.Option.textureUsage: MTLTextureUsage.unknown.rawValue,
                MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue
            ]
        ) else {
            print("Failed to create texture from image data!")
            return nil
        }
        self.texture = texture
        
        // Create a 32x32 destination texture
        let resizedTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: resizedSize,
            height: resizedSize,
            mipmapped: false
        )
        resizedTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let resizedTexture = device.makeTexture(descriptor: resizedTextureDescriptor) else {
            print("Failed to create \(resizedSize)x\(resizedSize) destination texture.")
            return nil
        }
        self.resizedTexture = resizedTexture
        
        // Create a 32x32 grayscale texture
        let grayscaleTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: resizedSize,
            height: resizedSize,
            mipmapped: false
        )
        grayscaleTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let grayscaleTexture = device.makeTexture(descriptor: grayscaleTextureDescriptor) else {
            print("Failed to create \(resizedSize)x\(resizedSize) destination texture.")
            return nil
        }
        self.grayscaleTexture = grayscaleTexture
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            print("Failed to create command queue!")
            return nil
        }
        self.commandQueue = commandQueue
    }
    
    // MARK: - Texture handling
    
    func perceptualHash() async throws -> String? {
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create command buffer!")
            return nil
        }
        
        // MARK: - Resize
        
        // Resize the image to target 32x32 resolution
        let resize = MPSImageBilinearScale(device: device)
        var transform = MPSScaleTransform(
            scaleX: Double(resizedSize) / Double(texture.width),
            scaleY: Double(resizedSize) / Double(texture.height),
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
        
        // MARK: - Grayscale
        
        // Create compute command encoder
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create compute command encoder!")
            return nil
        }
        
        // Set the PSO to perform a grayscale conversion
        computeEncoder.setComputePipelineState(grayscalePSO)
        
        // Set the source texture
        computeEncoder.setTexture(resizedTexture, index: 0)
        
        // Set the output texture
        computeEncoder.setTexture(grayscaleTexture, index: 1)
        
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
        
        // MARK: - Finish
        
        let hash = await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                let hash = self.computeDCT(grayscaleTexture: self.grayscaleTexture)
                continuation.resume(returning: hash)
            }
            // Submit work to the GPU
            commandBuffer.commit()
        }
        return hash
    }
    
    // MARK: - Compute DCT
    
    private func computeDCT(grayscaleTexture: MTLTexture) -> String {
        let rowBytes = resizedSize * 4
        let length = rowBytes * resizedSize
        let region = MTLRegionMake2D(0, 0, resizedSize, resizedSize)
        var grayBytes = [Float32](repeating: 0, count: length)
        var dctArray = [Float](repeating: 0, count: dctSize * dctSize)
        
        var hash: String = ""
        
        // Fill with the texture data
        grayBytes.withUnsafeMutableBytes { r32BytesPointer in
            guard let baseAddress = r32BytesPointer.baseAddress else {
                return
            }
            // Fill the array with data from the grayscale texture
            grayscaleTexture.getBytes(
                baseAddress,
                bytesPerRow: rowBytes,
                from: region,
                mipmapLevel: 0
            )
        }
        // Compute each one of the elements of the discrete cosine transform
        for u in 0..<dctSize {
            for v in 0..<dctSize {
                var pixel_sum: Float = 0
                for i in 0..<resizedSize {
                    var pixel_row_sum: Float = 0
                    // Compute the discrete cosine along the row axis
                    for j in 0..<resizedSize {
                        let pixelValue = grayBytes[i * resizedSize + j]
                        pixel_row_sum += pixelValue
                            * cos((Float.pi * (2.0 * Float(j) + 1.0) * Float(u)) / (2.0 * Float(resizedSize)))
                    }
                    pixel_row_sum *= cos((Float.pi * (2.0 * Float(i) + 1.0) * Float(v)) / (2.0 * Float(resizedSize)))
                    pixel_sum += pixel_row_sum
                }
                if u != 0 {
                    pixel_sum *= sqrt(2/Float(resizedSize))
                } else {
                    pixel_sum += sqrt(1/Float(resizedSize))
                }
                if v != 0 {
                    pixel_sum *= sqrt(2/Float(resizedSize))
                } else {
                    pixel_sum += sqrt(1/Float(resizedSize))
                }
                dctArray[u * dctSize + v] = pixel_sum
            }
        }
        
        // Remove zero order value at (0,0), as it throws off the mean
        dctArray[0] = 0.0
        
        // Compute the mean of all the elements in the image
        var meanDCT: Float = 0.0
        for u in 0..<dctSize {
            for v in 0..<dctSize {
                let dctValue = dctArray[u * dctSize + v]
                meanDCT += dctValue
            }
        }
        meanDCT /= Float(dctSize * dctSize)
        
        // Compute the hash comparing with the mean
        for i in 0..<(dctSize * dctSize) {
            if dctArray[i] > Float32(meanDCT) {
                hash += "1"
            } else {
                hash += "0"
            }
        }
        return binaryToHex(hash)
    }
    
    // MARK: - Hex
    
    private func binaryToHex(_ binary : String) -> String {
        let number = binary.withCString {
            // String to Unsigned long
            strtoul($0, nil, 2)
        }
        let hex = String(number, radix: 36, uppercase: false)
        return hex
    }
}
