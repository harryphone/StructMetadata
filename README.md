# StructMetadata
## 前言
我们通过[上一篇文章](https://juejin.cn/post/6919034854159941645)可以知道，`Struct`通过`Mirror`解析发现，`Struct`的`type`本质就是`StructMetadata`。

## 用swift代码完整模拟`StructMetadata`
我们上来先嗨一下，提高点兴致，后面读源码有点枯燥。

我已经把翻译好的源码内容传到[GitHub](https://github.com/harryphone/StructMetadata)了，下下来就能直接看到运行结果

里面的`Teacher`类可以替成换自己的类，也可以增加替换属性，里面的注释已经写的很详细了。

## `Description`

有关于`Kind`的，在[上一篇文章](https://juejin.cn/post/6919034854159941645)中已经详细描述了，这里不再赘述，让我们回到前面定义`Description`的地方。
```C++
/// An out-of-line description of the type.
  TargetSignedPointer<Runtime, const TargetValueTypeDescriptor<Runtime> * __ptrauth_swift_type_descriptor> Description;
  
  template <typename Runtime, typename T>
using TargetSignedPointer = typename Runtime::template SignedPointer<T>;

```
我们看到修饰`Description`的是`TargetValueTypeDescriptor`，但是点开`TargetSignedPointer`定义发现是一个`SignedPointer<T>`的指针，所以具体内容还是得看范型`T`，`T`在这里传进来的是`TargetValueTypeDescriptor`。但我们要注意，定义`Description`的地方是`TargetStructMetadata`的子类`TargetValueMetadata`，所以我们回到父类`TargetStructMetadata`的声明看下：
```C++
const TargetStructDescriptor<Runtime> *getDescription() const {
    return llvm::cast<TargetStructDescriptor<Runtime>>(this->Description);
  }

```
外部调用的`getDescription()`的方法里，把`Description`的`T`转化成了`TargetStructDescriptor`，所以真正的`T`就是`TargetStructDescriptor`，我们点开`TargetStructDescriptor`的定义：
```C++
template <typename Runtime>
class TargetStructDescriptor final
    : public TargetValueTypeDescriptor<Runtime>,
      public TrailingGenericContextObjects<TargetStructDescriptor<Runtime>,
                            TargetTypeGenericContextDescriptorHeader,
                            /*additional trailing objects*/
                            TargetForeignMetadataInitialization<Runtime>,
                            TargetSingletonMetadataInitialization<Runtime>> {
                            
 ...

  uint32_t NumFields;
  
  uint32_t FieldOffsetVectorOffset;
  
  ...
 }

```
这里出现了两个属性：
* `NumFields`：结构体中属性的个数
* `FieldOffsetVectorOffset`：如果我们打印结构体实例的内存，会发现属性的值按各自的对其方式直接依次存放在内存中，那么如果程序要取值，如何快速的定位呢？其实有一段内存记录了每个属性的起始位置的，他以4个字节的大小，像数组一样依次存了每个属性的起始位置，那么这段内存在哪呢？这段内存其实就紧挨着`StructMetadata`后面，当然，这个只是我测下来的结果。正确的做法就是取`FieldOffsetVectorOffset`，这个值就是记录了这段内存在`StructMetadata`首地址向后的偏移量。我打印出来是2，就是2个指针的长度，也就是紧挨着`StructMetadata`后面了。

`Description`的探索还没有完成，我们还得看父类中有没有属性，这里发现多继承了，我们点开`TrailingGenericContextObjects`里没有属性（这个类有点深，后面贴上我转换的源码），所以我们的关注点在`TargetValueTypeDescriptor`（绕了一圈又回来啦）。

## `TargetValueTypeDescriptor`
我们看下`TargetValueTypeDescriptor`的代码：
```C++
template <typename Runtime>
class TargetValueTypeDescriptor
    : public TargetTypeContextDescriptor<Runtime> {
public:
  static bool classof(const TargetContextDescriptor<Runtime> *cd) {
    return cd->getKind() == ContextDescriptorKind::Struct ||
           cd->getKind() == ContextDescriptorKind::Enum;
  }
};

```
没看到什么有价值的东西，继续看父类：`TargetTypeContextDescriptor`
```C++
template <typename Runtime>
class TargetTypeContextDescriptor
    : public TargetContextDescriptor<Runtime> {
public:
  TargetRelativeDirectPointer<Runtime, const char, /*nullable*/ false> Name;

  TargetRelativeDirectPointer<Runtime, MetadataResponse(...),
                              /*Nullable*/ true> AccessFunctionPtr;
  
  TargetRelativeDirectPointer<Runtime, const reflection::FieldDescriptor,
                              /*nullable*/ true> Fields;
  ...
};
```

发现3个属性：`Name`、`AccessFunctionPtr`、`Fields`：
* `Name`：结构体的名字
* `AccessFunctionPtr`：这里的函数类型是一个替身，需要调用getAccessFunction()拿到真正的函数指针，会得到一个MetadataAccessFunction元数据访问函数的指针的包装器类，该函数提供operator()重载以使用正确的调用约定来调用它
* `Fields`： 一个指向类型的字段描述符的指针(如果有的话)。类型字段的描述，可以从里面获取结构体的属性。

这些属性都是`TargetRelativeDirectPointer`修饰的，这个后面单独讲这个类，我们再看父类有没有属性：

```C++
struct TargetContextDescriptor {
  /// Flags describing the context, including its kind and format version.
  ContextDescriptorFlags Flags;
  
  /// The parent context, or null if this is a top-level context.
  TargetRelativeContextPointer<Runtime> Parent;
  ...
};
```

这里发现了2个属性：
* `Flags`：存储在任何上下文描述符的第一个公共标记。点开`ContextDescriptorFlags`，发现他本质就是一个`uint32_t`值，然后提供了很多方法，用位运算返回很多标记，例如类型、版本号等。
* `Parent`：父级上下文，如果是顶级上下文则为null。获得的类型为InProcess，里面存放的应该是一个指针，测下来结构体里为0，相当于null了。`TargetRelativeContextPointer`原理上和`TargetRelativeDirectPointer`差不多，看`TargetRelativeDirectPointer`就行了。

到此为止，已经没有父类了，所以我们可以算出一共有7个属性，可以转成`Swift`代码就是这样的：
```swift
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
```
## `TargetRelativeDirectPointer`
上面多次出现了`TargetRelativeDirectPointer`，这个到底是什么呢？我们看下定义：
```C++
using TargetRelativeDirectPointer
  = typename Runtime::template RelativeDirectPointer<Pointee, Nullable>;
  
  template <typename T, bool Nullable = true, typename Offset = int32_t,
          typename = void>
class RelativeDirectPointer;

  /// A direct relative reference to an object that is not a function pointer.
template <typename T, bool Nullable, typename Offset>
class RelativeDirectPointer<T, Nullable, Offset,
    typename std::enable_if<!std::is_function<T>::value>::type>
    : private RelativeDirectPointerImpl<T, Nullable, Offset>
{
  using super = RelativeDirectPointerImpl<T, Nullable, Offset>;
public:
  using super::get;
  using super::super;
  
  RelativeDirectPointer &operator=(T *absolute) & {
    super::operator=(absolute);
    return *this;
  }

  operator typename super::PointerTy() const & {
    return this->get();
  }

  const typename super::ValueTy *operator->() const & {
    return this->get();
  }

  using super::isNull;
};
```

先是一个别名，然后在`RelativeDirectPointer`没有看到特别有价值的东西，有几个操作调用了`get()`方法，所以我们还得要看父类`RelativeDirectPointerImpl`：
```C++
template<typename T, bool Nullable, typename Offset>
class RelativeDirectPointerImpl {
private:
  Offset RelativeOffset;
...
public:
...
  using ValueTy = T;
  using PointerTy = T*;

...
  PointerTy get() const & {
    // Check for null.
    if (Nullable && RelativeOffset == 0)
      return nullptr;
    
    // The value is addressed relative to `this`.
    uintptr_t absolute = detail::applyRelativeOffset(this, RelativeOffset);
    return reinterpret_cast<PointerTy>(absolute);
  }
...
};
```
我把最关键的的代码copy过来了，整个`RelativeDirectPointerImpl`就一个属性`RelativeOffset`，那么`Offset`是什么，我们看到这个`Offset`是一个模版属性，从子类中传过来就是`int32_t`。

而`T`是外部传进来的一个范型，所以`ValueTy`指的是范型的值本身，`PointerTy`是范型的值所在的指针地址。

`get()`最后返回出来的是个`PointerTy`的指针，拿到`PointerTy`的指针地址，就很容易拿到`ValueTy`范型的值。所以这个类的作用我们就清晰了，就是拿到一个传入范型的值，举个例子，比如上面`TargetRelativeDirectPointer<Runtime, const char, /*nullable*/ false> Name;`，我们通过调用`Name.get()`就能获取到`char *`的指针，就能得到`Name`的名字了。

那么如何获得指针地址的呢？关键调用了`detail::applyRelativeOffset(this, RelativeOffset);`方法，我们点开看下，看看他是怎么做的：
```C++
template<typename BasePtrTy, typename Offset>
static inline uintptr_t applyRelativeOffset(BasePtrTy *basePtr, Offset offset) {
  static_assert(std::is_integral<Offset>::value &&
                std::is_signed<Offset>::value,
                "offset type should be signed integer");

  auto base = reinterpret_cast<uintptr_t>(basePtr);
  auto extendOffset = (uintptr_t)(intptr_t)offset;
  return base + extendOffset;
}
```
很明显，就是把我们刚传进来的值相加一下，就得到了最后范型所在的地址。刚传进来的是`this`自己本身和`RelativeOffset`值，所以很明显了，把`RelativeDirectPointerImpl`所在的地址加上`RelativeOffset`的偏移量，就能获得范型所在的地址。有点像文件目录，用当前路径的相对路径获得绝对路径。

最后我们看下`RelativeDirectPointer`的`Swift`封装：
```swift
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

```

如果你自己封装的话，到这个时候，你已经可以拿到结构体的名字了。但前面我们还有一个范型`FieldDescriptor`没讲，他是修饰`Fields`的，他是描述各个属性的，解决完这个，我们`StructMetadata`解析的差不多了。

## `FieldDescriptor`
点开`FieldDescriptor`的定义：
```C++
class FieldDescriptor {
  const FieldRecord *getFieldRecordBuffer() const {
    return reinterpret_cast<const FieldRecord *>(this + 1);
  }

public:
  const RelativeDirectPointer<const char> MangledTypeName;
  const RelativeDirectPointer<const char> Superclass;

  const FieldDescriptorKind Kind;
  const uint16_t FieldRecordSize;
  const uint32_t NumFields;

 ...

  llvm::ArrayRef<FieldRecord> getFields() const {
    return {getFieldRecordBuffer(), NumFields};
  }
  
  ...
}
```
`FieldDescriptor`没有父类，那属性就是我们看到的5个了：
* `MangledTypeName`：类型命名重整，有了这个东西，就能支持我们`Swift`方法的重载
* `Superclass`：看名称是父类的样子，没测试 = =
* `Kind`：一个枚举，`FieldDescriptorKind`大小为`uint16_t`，看下源码定义：
```C++
enum class FieldDescriptorKind : uint16_t {
  Struct,
  Class,
  Enum,
  MultiPayloadEnum,
  Protocol,
  ClassProtocol,
  ObjCProtocol,
  ObjCClass
};
```
* `FieldRecordSize`：这个值乘上NumFields会拿到RecordSize，并不了解这个是干嘛的。。。
* `NumFields`：属性的个数，这个和上面的`NumFields`一样。

看到上面的属性，并没有发现有什么属性支持拿到属性的名称。但我们看到有个`getFields()`方法可以拿到属性的名称（问我是怎么知道的？当然断点调试`Mirror`源码拿到的），调用完这个方法后，可以拿到一个`FieldRecord`对象的数组。`FieldRecord`这个对象比较简单，就不带着看了，直接看我等会翻译的源码就行了，现在重点就是怎么拿到`FieldRecord`对象数组的。

我们可以看到`getFields()`中调用了`getFieldRecordBuffer()`方法，返回了一个`FieldRecord *`的指针，所以`FieldRecord`对象数组的起始位置就是`FieldRecord *`的指针。那怎么拿到`FieldRecord *`的指针地址？我们可以看到`getFieldRecordBuffer()`方法里直接强转了`(this + 1)`，就是以`FieldDescriptor`的大小为步长+1，换句话说，指针地址紧挨着`FieldDescriptor`的内容。

分析完了，我们看看怎么翻译成`Swift`的代码
```swift
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

```

## 结语

到此，我们`StructMetadata`内容基本上分析完了，如果要完整翻译代码，看文章的开头就是。当然，这个只是`StructMetadata`整个属性的面貌，还有很多细枝末节，说是细枝末节，但是点开看，发现无穷无尽。。。。

我还翻译了一些关于`StructMetadata`的源码，但是由于不知道是要干嘛的，所以分析起来很累，如果有点感觉的小伙伴可以看下，这块内容仅供参考，因为我也一知半解的（有点感觉了，但是还差一点，可能以后看其他模块，说不准有灵感触发）

内容放在这个文件里了[StructMetadataExtension](https://github.com/harryphone/StructMetadata/blob/main/StructMetadata/StructMetadataExtension.swift)，上面[GitHub](https://github.com/harryphone/StructMetadata)项目里包含
