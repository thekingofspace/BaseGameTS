/**
 * Type declarations for `Buffer.luau` — expanded buffer tooling.
 *
 * The module forwards every unknown index to the built-in `buffer` library
 * through `__index`, so it is a drop-in replacement. That is modelled here by
 * intersecting the module's own surface with `typeof buffer`:
 *
 * ```ts
 * const b = Buffer.create(16);   // built-in, reached through __index
 * Buffer.writeu32(b, 0, 1234);   // built-in
 * const grown = Buffer.Resize(b, 32); // added here
 * ```
 *
 * Built-in members keep their lowercase names; everything added by this module
 * is PascalCase, so the two sets can never collide.
 *
 * Buffers are fixed-size in Luau. Anything that changes a length (`Resize`,
 * `Grow`, `Slice`, `Concat`, ...) allocates a new buffer and returns it — it
 * cannot mutate the original in place, so always use the return value.
 *
 * Byte offsets are 0-based, matching the built-in library.
 *
 * Every module-level member is defined with a dot and takes no `self`, so they
 * are all declared as properties and compile to `Buffer.Foo(...)`. The
 * Writer/Reader/Pool/Arena objects take `self` on every entry, so those stay
 * method syntax and compile to colon calls.
 */

declare namespace Buffer {
	/** Byte width of each value type the module knows how to write. */
	interface Sizes {
		readonly i8: number;
		readonly u8: number;
		readonly i16: number;
		readonly u16: number;
		readonly i32: number;
		readonly u32: number;
		readonly f32: number;
		readonly f64: number;
		readonly bool: number;
		readonly Vector2: number;
		readonly Vector3: number;
		readonly CFrame: number;
		readonly Color3: number;
		readonly Color3Bytes: number;
		readonly UDim2: number;
	}

	/**
	 * A growable write cursor over an internal buffer. Every `Write*` returns
	 * the writer, so calls chain. Call `Build()` to take the bytes out.
	 */
	interface Writer {
		WriteU8(value: number): Writer;
		WriteU16(value: number): Writer;
		WriteU32(value: number): Writer;
		WriteI8(value: number): Writer;
		WriteI16(value: number): Writer;
		WriteI32(value: number): Writer;
		WriteF32(value: number): Writer;
		WriteF64(value: number): Writer;
		/** One byte: `1` or `0`. */
		WriteBool(value: boolean): Writer;
		/** LEB128-style variable length unsigned integer. */
		WriteVarUInt(value: number): Writer;
		/** Zig-zag encoded variable length signed integer. */
		WriteVarInt(value: number): Writer;
		/** Length-prefixed (varuint) string. */
		WriteString(value: string): Writer;
		/** The string's bytes with no length prefix. */
		WriteRaw(value: string): Writer;
		WriteBuffer(source: buffer, offset?: number, count?: number): Writer;
		WriteVector2(value: Vector2): Writer;
		WriteVector3(value: Vector3): Writer;
		WriteCFrame(value: CFrame): Writer;
		/** Three f32 components. */
		WriteColor3(value: Color3): Writer;
		/** Three bytes — lossy, but a quarter of the size. */
		WriteColor3Bytes(value: Color3): Writer;
		WriteUDim2(value: UDim2): Writer;
		/** Writes a `string.pack` payload at the cursor. */
		WritePacked(format: string, ...values: Array<unknown>): Writer;
		/** Advances the cursor over `count` bytes without writing them. */
		Pad(count: number): Writer;
		/** Pads until the cursor sits on a multiple of `alignment`. */
		Align(alignment: number): Writer;
		/** Moves the cursor. Does not shrink the written length. */
		Seek(position: number): Writer;
		/** Current cursor position. */
		Tell(): number;
		/** Highest byte written so far. */
		Length(): number;
		/** Size of the backing buffer, which is >= `Length()`. */
		Capacity(): number;
		/** Grows the backing buffer so `extra` more bytes fit without a realloc. */
		Reserve(extra: number): Writer;
		/** Rewinds the cursor and the written length to zero, keeping capacity. */
		Reset(): Writer;
		/** Copies the written bytes out into a right-sized buffer. */
		Build(): buffer;
		/** The written bytes as a Lua string. */
		ToString(): string;
	}

	/**
	 * A read cursor over a buffer. The `Read*` calls mirror `Writer`'s
	 * `Write*` calls one-for-one and advance the cursor.
	 */
	interface Reader {
		ReadU8(): number;
		ReadU16(): number;
		ReadU32(): number;
		ReadI8(): number;
		ReadI16(): number;
		ReadI32(): number;
		ReadF32(): number;
		ReadF64(): number;
		ReadBool(): boolean;
		ReadVarUInt(): number;
		ReadVarInt(): number;
		/** Reads a length-prefixed string written by `Writer.WriteString`. */
		ReadString(): string;
		/** Reads `count` raw bytes as a string. */
		ReadRaw(count: number): string;
		ReadBuffer(count: number): buffer;
		ReadVector2(): Vector2;
		ReadVector3(): Vector3;
		ReadCFrame(): CFrame;
		ReadColor3(): Color3;
		ReadColor3Bytes(): Color3;
		ReadUDim2(): UDim2;
		/** Unpacks `size` bytes with `string.unpack`. */
		ReadPacked(format: string, size: number): LuaTuple<Array<unknown>>;
		/** Skips `count` bytes. */
		Skip(count: number): Reader;
		/** Skips until the cursor sits on a multiple of `alignment`. */
		Align(alignment: number): Reader;
		Seek(position: number): Reader;
		Tell(): number;
		/** Bytes left between the cursor and the end. */
		Remaining(): number;
		IsFinished(): boolean;
		/** Rewinds the cursor to zero. */
		Reset(): Reader;
		/** The buffer being read. */
		Source(): buffer;
	}

	interface PoolStats {
		/** Blocks handed out and not released back. */
		Live: number;
		/** Blocks sitting idle in the pool. */
		Pooled: number;
		/** `Get` calls served from the pool. */
		Hits: number;
		/** `Get` calls that had to allocate. */
		Misses: number;
		/** Idle count per size class. */
		Classes: Map<number, number>;
	}

	/**
	 * A free-list of buffers bucketed into power-of-two size classes, so churn
	 * on same-sized scratch buffers stops allocating.
	 */
	interface Pool {
		/** Returns a buffer of at least `size` bytes, rounded up to a size class. */
		Get(size: number): buffer;
		/**
		 * Hands a block back. Returns `false` (and drops it) when the block is
		 * not a poolable size class or the class is already full.
		 */
		Release(block: buffer): boolean;
		/** Fills a size class up front, up to the per-class cap. */
		Preallocate(size: number, count: number): void;
		Stats(): PoolStats;
		/** Drops every pooled block. Live blocks are unaffected. */
		Clear(): void;
	}

	/**
	 * A bump allocator over one backing buffer. Allocation is a cursor move;
	 * freeing is `Rewind`/`Reset` for the whole region at once.
	 */
	interface Arena {
		/** Reserves `size` bytes and returns their offset. Throws when full. */
		Alloc(size: number, alignment?: number): number;
		/** Like `Alloc`, but returns `undefined` instead of throwing. */
		TryAlloc(size: number, alignment?: number): number | undefined;
		/** Snapshots the cursor for a later `Rewind`. */
		Mark(): number;
		/** Frees everything allocated since `mark`. */
		Rewind(mark: number): void;
		/** Frees everything. */
		Reset(): void;
		/** The backing buffer — offsets from `Alloc` index into this. */
		Buffer(): buffer;
		Used(): number;
		Capacity(): number;
		Remaining(): number;
	}
}

interface BufferMethods {
	/** `Buffer(size)` is shorthand for `buffer.create(size)`. */
	(size: number): buffer;

	/** Byte width of every value type the module can write. Frozen. */
	readonly Sizes: Buffer.Sizes;

	// -------------------------------------------------------- Creation and sizing

	/** `buffer.create` with a validated, floored size. */
	new: (size: number) => buffer;
	/** Builds a buffer from a string, a copy of another buffer, or a byte array. */
	From: (value: string | buffer | Array<number>) => buffer;
	/** Returns a buffer of exactly `newSize` bytes, truncating or zero-padding. */
	Resize: (b: buffer, newSize: number) => buffer;
	/** `Resize` to the current length plus `extra` (negative shrinks). */
	Grow: (b: buffer, extra: number) => buffer;
	/** Shrinks to `size` bytes; never grows. */
	Truncate: (b: buffer, size: number) => buffer;
	/** Returns `b` untouched if it already holds `needed` bytes, else doubles it. */
	Reserve: (b: buffer, needed: number) => buffer;
	/** A byte-for-byte copy. */
	Clone: (b: buffer) => buffer;
	/** Copies the `[offset, offset + count)` window into a new buffer. */
	Slice: (b: buffer, offset?: number, count?: number) => buffer;
	/** Joins every argument end to end into one new buffer. */
	Concat: (...pieces: Array<buffer>) => buffer;
	/** Like `Concat`, but takes a list and puts `separator` between entries. */
	Join: (list: Array<buffer>, separator?: buffer) => buffer;
	/** Splits into `chunkSize`-byte buffers; the last one may be shorter. */
	Split: (b: buffer, chunkSize: number) => Array<buffer>;
	/** Concatenates `b` with itself `times` times. */
	Repeat: (b: buffer, times: number) => buffer;

	// -------------------------------------------------------- Inspection

	IsBuffer: (value: unknown) => value is buffer;
	IsEmpty: (b: buffer) => boolean;
	/** Reads the window out as a 1-based array of bytes. */
	ToArray: (b: buffer, offset?: number, count?: number) => Array<number>;
	/** True when every byte in the window is zero. */
	IsZeroed: (b: buffer, offset?: number, count?: number) => boolean;
	/** Number of times `byte` occurs in the window. */
	CountByte: (b: buffer, byte: number, offset?: number, count?: number) => number;

	// -------------------------------------------------------- Mutation (in place, returns `b`)

	/** Zero-fills the window. */
	Clear: (b: buffer, offset?: number, count?: number) => buffer;
	/** Copies a window onto another offset in the same buffer; overlap is safe. */
	CopyWithin: (b: buffer, to: number, from: number, count?: number) => buffer;
	/** Swaps two single bytes. */
	SwapBytes: (b: buffer, first: number, second: number) => buffer;
	/** Reverses the byte order of the window. */
	Reverse: (b: buffer, offset?: number, count?: number) => buffer;
	/**
	 * Flips endianness of every `width`-byte word in the window. `width` must
	 * be 2, 4 or 8 and must divide the window evenly.
	 */
	ByteSwap: (b: buffer, width: number, offset?: number, count?: number) => buffer;

	// -------------------------------------------------------- Comparison and search

	/** Same length and same bytes. Compares a word at a time. */
	Equals: (a: buffer, b: buffer) => boolean;
	/** Lexicographic compare: `-1`, `0` or `1`. Shorter sorts first on a tie. */
	Compare: (a: buffer, b: buffer) => number;
	/** Constant-time `Equals` for secrets — no early exit on the first mismatch. */
	SecureEquals: (a: buffer, b: buffer) => boolean;
	/** Offset of the first occurrence of `needle` at or after `init`. */
	Find: (haystack: buffer, needle: buffer, init?: number) => number | undefined;
	/** Offset of the first occurrence of a single byte at or after `init`. */
	FindByte: (b: buffer, byte: number, init?: number) => number | undefined;
	StartsWith: (b: buffer, prefix: buffer) => boolean;
	EndsWith: (b: buffer, suffix: buffer) => boolean;

	// -------------------------------------------------------- Bit-level access

	/** `0` or `1`. Bit indices are 0-based and run LSB-first inside each byte. */
	GetBit: (b: buffer, bitIndex: number) => number;
	/** `GetBit(...) == 1`. */
	TestBit: (b: buffer, bitIndex: number) => boolean;
	SetBit: (b: buffer, bitIndex: number, value: boolean | number) => buffer;
	FlipBit: (b: buffer, bitIndex: number) => buffer;
	/** Number of set bits in the window. */
	PopCount: (b: buffer, offset?: number, count?: number) => number;
	/**
	 * Bitwise AND over `min(#a, #b)` bytes. Writes into `out` when given
	 * (it must be long enough), otherwise allocates the result.
	 */
	BitAnd: (a: buffer, b: buffer, out?: buffer) => buffer;
	/** Bitwise OR — see `BitAnd` for the `out` rules. */
	BitOr: (a: buffer, b: buffer, out?: buffer) => buffer;
	/** Bitwise XOR — see `BitAnd` for the `out` rules. */
	BitXor: (a: buffer, b: buffer, out?: buffer) => buffer;
	/** Inverts the window in place and returns `b`. */
	BitNot: (b: buffer, offset?: number, count?: number) => buffer;

	// -------------------------------------------------------- Big-endian primitives

	/** Reverses the two bytes of a 16-bit value. */
	Swap16: (value: number) => number;
	/** Reverses the four bytes of a 32-bit value. */
	Swap32: (value: number) => number;
	ReadU16BE: (b: buffer, offset: number) => number;
	WriteU16BE: (b: buffer, offset: number, value: number) => void;
	ReadU32BE: (b: buffer, offset: number) => number;
	WriteU32BE: (b: buffer, offset: number, value: number) => void;

	// -------------------------------------------------------- string.pack bridge

	/** Packs the values at `offset` and returns the offset just past them. */
	WritePacked: (b: buffer, offset: number, format: string, ...values: Array<unknown>) => number;
	/**
	 * Unpacks `size` bytes at `offset`. The last returned value is the offset
	 * just past the read, replacing `string.unpack`'s own position value.
	 */
	ReadPacked: (b: buffer, offset: number, format: string, size: number) => LuaTuple<Array<unknown>>;

	// -------------------------------------------------------- Variable-length integers

	/** Bytes `WriteVarUInt` would need for this value. */
	VarUIntSize: (value: number) => number;
	/** Writes a LEB128-style varint. Returns the offset just past it. */
	WriteVarUInt: (b: buffer, offset: number, value: number) => number;
	/** Returns `(value, nextOffset)`. Throws past 53 bits. */
	ReadVarUInt: (b: buffer, offset: number) => LuaTuple<[number, number]>;
	/** Zig-zag encodes, then writes as a varuint. Returns the offset past it. */
	WriteVarInt: (b: buffer, offset: number, value: number) => number;
	/** Returns `(value, nextOffset)`. */
	ReadVarInt: (b: buffer, offset: number) => LuaTuple<[number, number]>;

	// -------------------------------------------------------- Roblox datatypes
	// Every Write* returns the offset just past the write; every Read* returns
	// `(value, nextOffset)`.

	WriteVector2: (b: buffer, offset: number, value: Vector2) => number;
	ReadVector2: (b: buffer, offset: number) => LuaTuple<[Vector2, number]>;
	WriteVector3: (b: buffer, offset: number, value: Vector3) => number;
	ReadVector3: (b: buffer, offset: number) => LuaTuple<[Vector3, number]>;
	WriteCFrame: (b: buffer, offset: number, value: CFrame) => number;
	ReadCFrame: (b: buffer, offset: number) => LuaTuple<[CFrame, number]>;
	/** Three f32 components — 12 bytes, full precision. */
	WriteColor3: (b: buffer, offset: number, value: Color3) => number;
	ReadColor3: (b: buffer, offset: number) => LuaTuple<[Color3, number]>;
	/** Three bytes — lossy, but a quarter of the size. */
	WriteColor3Bytes: (b: buffer, offset: number, value: Color3) => number;
	ReadColor3Bytes: (b: buffer, offset: number) => LuaTuple<[Color3, number]>;
	WriteUDim2: (b: buffer, offset: number, value: UDim2) => number;
	ReadUDim2: (b: buffer, offset: number) => LuaTuple<[UDim2, number]>;

	// -------------------------------------------------------- Encoding

	/** Uppercase hex, optionally separated (e.g. `" "` for `"DE AD"`). */
	ToHex: (b: buffer, separator?: string) => string;
	/** Parses hex text back into bytes. Non-hex separators are skipped. */
	FromHex: (text: string) => buffer;
	ToBase64: (b: buffer) => string;
	FromBase64: (text: string) => buffer;
	/**
	 * `xxd`-style dump: offset column, hex column, ASCII column. Returns
	 * `"(empty buffer)"` for a zero-length buffer. `bytesPerRow` defaults to 16.
	 */
	HexDump: (b: buffer, bytesPerRow?: number) => string;

	// -------------------------------------------------------- Checksums

	/** CRC-32 (IEEE) over the window. */
	CRC32: (b: buffer, offset?: number, count?: number) => number;
	/** Adler-32 over the window. */
	Adler32: (b: buffer, offset?: number, count?: number) => number;
	/** 32-bit FNV-1a over the window. */
	FNV1a32: (b: buffer, offset?: number, count?: number) => number;

	// -------------------------------------------------------- Factories

	/** A growable writer. `capacity` defaults to 64 bytes. */
	Writer: (capacity?: number) => Buffer.Writer;
	/** A reader over a buffer, or over a string converted to one. */
	Reader: (source: buffer | string) => Buffer.Reader;
	/** A size-class buffer pool. `maxPerClass` defaults to 32. */
	Pool: (maxPerClass?: number) => Buffer.Pool;
	/**
	 * A bump allocator over `capacity` bytes (minimum 16). `growable` defaults
	 * to `true`.
	 */
	Arena: (capacity: number, growable?: boolean) => Buffer.Arena;
}

/**
 * The module's own PascalCase surface plus every lowercase member of the
 * built-in `buffer` library, which `__index` forwards to.
 */
type BufferModule = BufferMethods & typeof buffer;

declare const Buffer: BufferModule;

export = Buffer;
