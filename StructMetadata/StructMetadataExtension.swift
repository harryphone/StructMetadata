//
//  StructMetadataExtension.swift
//  StructMetadata
//
//  Created by HarryPhone on 2021/1/21.
//

import Foundation

protocol FlagSet {
    associatedtype IntType : FixedWidthInteger
    var Bits: IntType { get set }
    
    func lowMaskFor(_ BitWidth: Int) -> IntType

    func maskFor(_ FirstBit: Int) -> IntType

    func getFlag(_ Bit: Int) -> Bool

    func getField(_ FirstBit: Int, _ BitWidth: Int) -> IntType
}

extension FlagSet {
    func lowMaskFor(_ BitWidth: Int) -> IntType {
        return IntType((1 << BitWidth) - 1)
    }

    func maskFor(_ FirstBit: Int) -> IntType {
        return lowMaskFor(1) << FirstBit
    }

    func getFlag(_ Bit: Int) -> Bool {
        return ((Bits & maskFor(Bit)) != 0)
    }

    func getField(_ FirstBit: Int, _ BitWidth: Int) -> IntType {
        return IntType((Bits >> FirstBit) & lowMaskFor(BitWidth));
    }
}

//以下内容仅供参考
extension StructMetadata {
    mutating func getTrailingFlags() -> UnsafeMutablePointer<MetadataTrailingFlags>? {
        let patternFlags = self.Description.pointee.getFullGenericContextHeader().pointee.DefaultInstantiationPattern.get().pointee.PatternFlags
        if !patternFlags.getFlag(GenericMetadataPatternFlags.Pattern.HasTrailingFlags.rawValue) {
            return nil
        }
        // 获取fieldOffsetVectorOffset的偏移量
        let fieldOffsetVectorOffset = self.Description.pointee.FieldOffsetVectorOffset
        // 获取属性的个数
        let numFields = self.Description.pointee.NumFields
        // 把sizeof(void *)翻译成swift代码
        let voidSize = MemoryLayout<UnsafeRawPointer>.size
        // 源码翻译过来的运算，其实就是过掉fieldOffsetVectorOffset中的内容，取下一个指针的偏移量。
        let offset = (Int(numFields) * MemoryLayout<UInt32>.size + voidSize - 1) / voidSize + Int(fieldOffsetVectorOffset)
        return withUnsafeMutablePointer(to: &self) {
            // 获得自己本身的起始位置
            let selfPtr = UnsafeMutableRawPointer($0).assumingMemoryBound(to: InProcess.self)
            // 以指针的步长偏移offset
            let offsetPtr = selfPtr.advanced(by: numericCast(offset))
            // 转一下指针
            return UnsafeMutableRawPointer(offsetPtr).assumingMemoryBound(to: MetadataTrailingFlags.self)
        }
    }
    
    struct MetadataTrailingFlags: FlagSet {
        
        enum Specialization: Int {
            /// Whether this metadata is a specializaxtion of a generic metadata pattern
            /// which was created during compilation.
            case IsStaticSpecialization = 0
            
            /// Whether this metadata is a specialization of a generic metadata pattern
            /// which was created during compilation and made to be canonical by
            /// modifying the metadata accessor.
            case IsCanonicalStaticSpecialization = 1
            }
        
        typealias IntType = UInt64
        var Bits: IntType
        
    }
}

extension TargetStructDescriptor {
    mutating func getFullGenericContextHeader() -> UnsafeMutablePointer<TargetTypeGenericContextDescriptorHeader> {
        return withUnsafeMutablePointer(to: &self) {
            return UnsafeMutableRawPointer($0.advanced(by: 1)).assumingMemoryBound(to: TargetTypeGenericContextDescriptorHeader.self)
        }
    }
}


struct TargetGenericContextDescriptorHeader {
    var NumParams: UInt16
    var NumRequirements: UInt16
    var NumKeyArguments: UInt16
    var NumExtraArguments: UInt16
 
    func getNumArguments() -> UInt32 {
        return numericCast(NumKeyArguments + NumExtraArguments)
    }
    
    func hasArguments() -> Bool {
        return getNumArguments() > 0
    }
}

/// The instantiation cache for generic metadata.  This must be guaranteed
/// to zero-initialized before it is first accessed.  Its contents are private
/// to the runtime.
struct TargetGenericMetadataInstantiationCache {
  /// Data that the runtime can use for its own purposes.  It is guaranteed
  /// to be zero-filled by the compiler.
//  TargetPointer<Runtime, void>
//  PrivateData[swift::NumGenericMetadataPrivateDataWords];
    var PrivateData: UnsafePointer<UnsafeRawPointer>
}

struct GenericMetadataPatternFlags: FlagSet {
    
    enum Pattern: Int {
        // All of these values are bit offsets or widths.
        // General flags build up from 0.
        // Kind-specific flags build down from 31.

        /// Does this pattern have an extra-data pattern?
        case HasExtraDataPattern = 0

        /// Do instances of this pattern have a bitset of flags that occur at the
        /// end of the metadata, after the extra data if there is any?
        case HasTrailingFlags = 1

        // Class-specific flags.

        /// Does this pattern have an immediate-members pattern?
        case Class_HasImmediateMembersPattern = 31

        // Value-specific flags.

        /// For value metadata: the metadata kind of the type.
        case Value_MetadataKind = 21
        case Value_MetadataKind_width = 11
      };
    
    typealias IntType = UInt32
    var Bits: IntType
}

struct Metadata {
    var Kind: InProcess
}


/// A dependency on the metadata progress of other type, indicating that
/// initialization of a metadata cannot progress until another metadata
/// reaches a particular state.
///
/// For performance, functions returning this type should use SWIFT_CC so
/// that the components are returned as separate values.
struct MetadataDependency {
  /// Either null, indicating that initialization was successful, or
  /// a metadata on which initialization depends for further progress.
    var Value: UnsafePointer<Metadata>

  /// The state that Metadata needs to be in before initialization
  /// can continue.
    typealias MetadataState = InProcess
    var Requirement: MetadataState
}

/// An instantiation pattern for type metadata.
struct TargetGenericMetadataPattern {
  /// The function to call to instantiate the template.
//    var InstantiationFunction: RelativeDirectPointer<MetadataInstantiator>
    var InstantiationFunction: RelativeDirectPointer<Metadata>

  /// The function to call to complete the instantiation.  If this is null,
  /// the instantiation function must always generate complete metadata.

    var CompletionFunction: RelativeDirectPointer<MetadataDependency>

  /// Flags describing the layout of this instantiation pattern.
    var PatternFlags: GenericMetadataPatternFlags

//  bool hasExtraDataPattern() const {
//    return PatternFlags.hasExtraDataPattern();
//  }
};

struct TargetTypeGenericContextDescriptorHeader {
    /// The metadata instantiation cache.
    var InstantiationCache: RelativeDirectPointer<TargetGenericMetadataInstantiationCache>
    var DefaultInstantiationPattern: RelativeDirectPointer<TargetGenericMetadataPattern>
    /// The base header.  Must always be the final member.
    var Base: TargetGenericContextDescriptorHeader
}
