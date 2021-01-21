//
//  main.swift
//  StructMetadata
//
//  Created by HarryPhone on 2021/1/21.
//

import Foundation

// 进程内的本机运行时目标。对于运行时中的交互，这应该等同于使用普通的老式指针类型。
// 个人理解下来就是一个指针大小的空间，在OC的Class中就是isa指针，在swift原生类型中放的是MetaKind。相当于在swift中的所有Type，首个指针大小的空间中，存放了区分Type的数据
struct InProcess {
    var PointerSize: UInt
}

struct StructMetadata {
    var Kind: InProcess   // MetadataKind，结构体的枚举值是0x200
    var Description: UnsafeMutablePointer<TargetStructDescriptor>// 结构体的描述，包含了结构体的所有信息，是一个指针
    
    //获得每个属性的在结构体中内存的起始位置
    mutating func getFieldOffset(index: Int) -> Int {
        if Description.pointee.NumFields == 0 {
            print("结构体没有属性")
            return 0
        }
        let fieldOffsetVectorOffset = self.Description.pointee.FieldOffsetVectorOffset
        return withUnsafeMutablePointer(to: &self) {
            //获得自己本身的起始位置
            let selfPtr = UnsafeMutableRawPointer($0).assumingMemoryBound(to: InProcess.self)
            //以指针的步长偏移FieldOffsetVectorOffset
            let fieldOffsetVectorOffsetPtr = selfPtr.advanced(by: numericCast(fieldOffsetVectorOffset))
            //属性的起始偏移量已32位整形存储的，转一下指针
            let tramsformPtr = UnsafeMutableRawPointer(fieldOffsetVectorOffsetPtr).assumingMemoryBound(to: UInt32.self)
            return numericCast(tramsformPtr.advanced(by: index).pointee)
        }
    }
}





struct TargetStructDescriptor {
    // 存储在任何上下文描述符的第一个公共标记
    var Flags: ContextDescriptorFlags

    // 复用的RelativeDirectPointer这个类型，其实并不是，但看下来原理一样
    // 父级上下文，如果是顶级上下文则为null。获得的类型为InProcess，里面存放的应该是一个指针，测下来结构体里为0，相当于null了
    var Parent: RelativeDirectPointer<InProcess>

    // 获取Struct的名称
    var Name: RelativeDirectPointer<CChar>

    // 这里的函数类型是一个替身，需要调用getAccessFunction()拿到真正的函数指针（这里没有封装），会得到一个MetadataAccessFunction元数据访问函数的指针的包装器类，该函数提供operator()重载以使用正确的调用约定来调用它（可变长参数），意外发现命名重整会调用这边的方法（目前不太了解这块内容）。
    var AccessFunctionPtr: RelativeDirectPointer<UnsafeRawPointer>

    // 一个指向类型的字段描述符的指针(如果有的话)。类型字段的描述，可以从里面获取结构体的属性。
    var Fields: RelativeDirectPointer<FieldDescriptor>
    // 结构体属性个数
    var NumFields: Int32
    // 存储这个结构的字段偏移向量的偏移量（记录你属性起始位置的开始的一个相对于metadata的偏移量，具体看metadata的getFieldOffsets方法），如果为0，说明你没有属性
    var FieldOffsetVectorOffset: Int32

}

struct ContextDescriptorFlags {

    enum ContextDescriptorKind: UInt8 {
        case Module = 0         //表示一个模块
        case Extension          //表示一个扩展
        case Anonymous          //表示一个匿名的可能的泛型上下文，例如函数体
        case kProtocol          //表示一个协议
        case OpaqueType         //表示一个不透明的类型别名
        case Class = 16         //表示一个类
        case Struct             //表示一个结构体
        case Enum               //表示一个枚举
    }

    var Value: UInt32

    /// The kind of context this descriptor describes.
    func getContextDescriptorKind() -> ContextDescriptorKind? {
        return ContextDescriptorKind.init(rawValue: numericCast(Value & 0x1F))
    }

    /// Whether the context being described is generic.
    func isGeneric() -> Bool {
        return (Value & 0x80) != 0
    }

    /// Whether this is a unique record describing the referenced context.
    func isUnique() -> Bool {
        return (Value & 0x40) != 0
    }

    /// The format version of the descriptor. Higher version numbers may have
    /// additional fields that aren't present in older versions.
    func getVersion() -> UInt8 {
        return numericCast((Value >> 8) & 0xFF)
    }

    /// The most significant two bytes of the flags word, which can have
    /// kind-specific meaning.
    func getKindSpecificFlags() -> UInt16 {
        return numericCast((Value >> 16) & 0xFFFF)
    }
}



struct FieldDescriptor {

    enum FieldDescriptorKind: UInt16 {
        case Struct
        case Class
        case Enum
        // Fixed-size multi-payload enums have a special descriptor format that encodes spare bits.
        case MultiPayloadEnum
        // A Swift opaque protocol. There are no fields, just a record for the type itself.
        case kProtocol
        // A Swift class-bound protocol.
        case ClassProtocol
        // An Objective-C protocol, which may be imported or defined in Swift.
        case ObjCProtocol
        // An Objective-C class, which may be imported or defined in Swift.
        // In the former case, field type metadata is not emitted, and must be obtained from the Objective-C runtime.
        case ObjCClass
    }

    var MangledTypeName: RelativeDirectPointer<CChar>//类型命名重整
    var Superclass: RelativeDirectPointer<CChar>//父类名
    var Kind: FieldDescriptorKind//类型，看枚举
    var FieldRecordSize: Int16 //这个值乘上NumFields会拿到RecordSize
    var NumFields: Int32//还是属性个数

    //获取每个属性，得到FieldRecord
    mutating func getField(index: Int) -> UnsafeMutablePointer<FieldRecord> {
        return withUnsafeMutablePointer(to: &self) {
            let arrayPtr = UnsafeMutableRawPointer($0.advanced(by: 1)).assumingMemoryBound(to: FieldRecord.self)
            return arrayPtr.advanced(by: index)
        }
    }
}

struct FieldRecord {

    struct FieldRecordFlags {

        var Data: UInt32

        /// Is this an indirect enum case?
        func isIndirectCase() -> Bool {
            return (Data & 0x1) == 0x1;
        }

        /// Is this a mutable `var` property?
        func isVar() -> Bool {
            return (Data & 0x2) == 0x2;
        }
    }

    var Flags: FieldRecordFlags //标记位
    var MangledTypeName: RelativeDirectPointer<CChar>//类型命名重整
    var FieldName: RelativeDirectPointer<CChar>//属性名
}

//这个类型是通过当前地址的偏移值获得真正的地址，有点像文件目录，用当前路径的相对路径获得绝对路径。
struct RelativeDirectPointer<T> {
    var offset: Int32 //存放的与当前地址的偏移值

    //通过地址的相对偏移值获得真正的地址
    mutating func get() -> UnsafeMutablePointer<T> {
        let offset = self.offset
        return withUnsafeMutablePointer(to: &self) {
            return UnsafeMutableRawPointer($0).advanced(by: numericCast(offset)).assumingMemoryBound(to: T.self)
        }
    }
}

struct Teacher: Codable {
    var name = "Tom"
    var age = 23
    var city = "ShangHai"
    var height = 175
}

// 通过源码我们可以知道Type类型对应的就是Metadata，这里记住要转成Any.Type，不然typesize不一致，不让转
let ptr = unsafeBitCast(Teacher.self as Any.Type, to: UnsafeMutablePointer<StructMetadata>.self)
print("0x\(String(ptr.pointee.Kind.PointerSize, radix: 16))") //kind枚举值是0x200，代表着结构体

let descriptionptr = ptr.pointee.Description

let Flags = descriptionptr.pointee.Flags
print(Flags.getContextDescriptorKind()!)  // 公共标记中获取kind为Struct

let ParentPtr = descriptionptr.pointee.Parent.get()
print(ParentPtr.pointee.PointerSize) // 结果为0，说明已经是顶级上下文了

let structName = descriptionptr.pointee.Name.get()
print(String(cString: structName)) // 拿到Teacher字符串

//拿到属性个数，属性名字，属性在内存的起始位置，这样就可以取值，mirror的原理就是这个！！
let propertyCount = Int(descriptionptr.pointee.NumFields)
print("属性个数：\(propertyCount)")
print("---------")
(0..<propertyCount).forEach {
    let propertyPtr = descriptionptr.pointee.Fields.get().pointee.getField(index: $0)
    print("""
        属性名：\(String(cString: propertyPtr.pointee.FieldName.get()))
        起始位置：\(ptr.pointee.getFieldOffset(index: $0))
        类型命名重整：\(String(cString: propertyPtr.pointee.MangledTypeName.get()))
        是否是var修饰的变量：\(propertyPtr.pointee.Flags.isVar() ? "是" : "否" )
        ---------
        """)
}

