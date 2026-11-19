var CompressionType;
(function (CompressionType) {
    /// Lossy compression using 2D delta coding and scale-factor.
    /// Only supports float and scales to 16-bit signed integer.
    CompressionType[CompressionType["PforDelta2dInt16"] = 0] = "PforDelta2dInt16";
    /// Lossless float/double compression using 2D xor coding.
    CompressionType[CompressionType["FpxXor2d"] = 1] = "FpxXor2d";
    /// PFor integer compression.
    /// f32 values are scaled to u32, f64 are scaled to u64.
    CompressionType[CompressionType["PforDelta2d"] = 2] = "PforDelta2d";
    /// Similar to `PforDelta2dInt16` but applies `log10(1+x)` before.
    CompressionType[CompressionType["PforDelta2dInt16Logarithmic"] = 3] = "PforDelta2dInt16Logarithmic";
    CompressionType[CompressionType["None"] = 4] = "None";
})(CompressionType || (CompressionType = {}));
var OmDataType;
(function (OmDataType) {
    OmDataType[OmDataType["None"] = 0] = "None";
    OmDataType[OmDataType["Int8"] = 1] = "Int8";
    OmDataType[OmDataType["Uint8"] = 2] = "Uint8";
    OmDataType[OmDataType["Int16"] = 3] = "Int16";
    OmDataType[OmDataType["Uint16"] = 4] = "Uint16";
    OmDataType[OmDataType["Int32"] = 5] = "Int32";
    OmDataType[OmDataType["Uint32"] = 6] = "Uint32";
    OmDataType[OmDataType["Int64"] = 7] = "Int64";
    OmDataType[OmDataType["Uint64"] = 8] = "Uint64";
    OmDataType[OmDataType["Float"] = 9] = "Float";
    OmDataType[OmDataType["Double"] = 10] = "Double";
    OmDataType[OmDataType["String"] = 11] = "String";
    OmDataType[OmDataType["Int8Array"] = 12] = "Int8Array";
    OmDataType[OmDataType["Uint8Array"] = 13] = "Uint8Array";
    OmDataType[OmDataType["Int16Array"] = 14] = "Int16Array";
    OmDataType[OmDataType["Uint16Array"] = 15] = "Uint16Array";
    OmDataType[OmDataType["Int32Array"] = 16] = "Int32Array";
    OmDataType[OmDataType["Uint32Array"] = 17] = "Uint32Array";
    OmDataType[OmDataType["Int64Array"] = 18] = "Int64Array";
    OmDataType[OmDataType["Uint64Array"] = 19] = "Uint64Array";
    OmDataType[OmDataType["FloatArray"] = 20] = "FloatArray";
    OmDataType[OmDataType["DoubleArray"] = 21] = "DoubleArray";
    OmDataType[OmDataType["StringArray"] = 22] = "StringArray";
})(OmDataType || (OmDataType = {}));

/**
 * Throws the signal's abort reason if the signal has been aborted.
 * Uses the standard DOMException with name "AbortError" as fallback.
 */
function throwIfAborted(signal) {
    if (signal?.throwIfAborted) {
        signal.throwIfAborted();
    }
    else if (signal?.aborted) {
        throw signal.reason ?? new DOMException("The operation was aborted", "AbortError");
    }
}
/**
 * FNV-1a 64-bit hash implementation
 */
function fnv1aHash64(str) {
    const FNV_OFFSET_BASIS = 0xcbf29ce484222325n;
    const FNV_PRIME = 0x100000001b3n;
    let hash = FNV_OFFSET_BASIS;
    const bytes = new TextEncoder().encode(str);
    for (const byte of bytes) {
        hash ^= BigInt(byte);
        hash = (hash * FNV_PRIME) & 0xffffffffffffffffn;
    }
    return hash;
}
/**
 * Fetch with exponential backoff retry on server-side errors (HTTP 5xx) and per-attempt timeout.
 */
async function fetchRetry(input, init, timeoutMs = 5000, retries = 3, signal) {
    let lastError;
    function withTimeout(promise, ms) {
        return Promise.race([
            promise,
            new Promise((_, reject) => setTimeout(() => reject(new Error(`Timeout after ${ms}ms`)), ms)),
        ]);
    }
    for (let attempt = 0; attempt < retries; attempt++) {
        throwIfAborted(signal);
        try {
            const mergedInit = { ...init };
            if (signal) {
                mergedInit.signal = signal;
            }
            const response = await withTimeout(fetch(input, mergedInit), timeoutMs);
            if (response.status >= 500 && response.status < 600) {
                throw new Error(`Server error: ${response.status}`);
            }
            return response;
        }
        catch (error) {
            // If the signal was aborted, re-throw immediately without retrying
            throwIfAborted(signal);
            lastError = error instanceof Error ? error : new Error(String(error));
            if (attempt < retries - 1) {
                const delay = Math.min(500 * Math.pow(2, attempt), 5000);
                //console.debug(`Attempt ${attempt + 1} failed, retrying in ${delay}ms: ${lastError.message}`);
                await new Promise((resolve) => setTimeout(resolve, delay));
            }
        }
    }
    throw lastError;
}
/**
 * Runs `tasks` with at most `limit` of them in flight, in order.
 *
 * `limit` workers pull from a shared queue rather than running fixed batches:
 * the signal is checked before every task, so an abort stops dispatching at
 * once instead of at the next batch boundary (which, with the default limit,
 * meant up to ten more requests were sent for a read nobody waits for). It
 * also keeps every slot busy when one task is slower than its neighbours.
 */
async function runLimited(tasks, limit, signal) {
    const results = new Array(tasks.length);
    let next = 0;
    let stopped = false;
    const worker = async () => {
        while (!stopped) {
            throwIfAborted(signal);
            const index = next++;
            if (index >= tasks.length)
                return;
            results[index] = await tasks[index]();
        }
    };
    const workers = [];
    for (let i = 0; i < Math.min(limit, tasks.length); i++) {
        workers.push(worker());
    }
    try {
        await Promise.all(workers);
    }
    finally {
        // Every worker has to come to a stop before this returns, or a failed run
        // would leave tasks dispatching behind it
        stopped = true;
        await Promise.allSettled(workers);
    }
    return results;
}

// Constants mapping
const DATA_TYPES = {
    DATA_TYPE_NONE: 0,
    DATA_TYPE_INT8: 1,
    DATA_TYPE_UINT8: 2,
    DATA_TYPE_INT16: 3,
    DATA_TYPE_UINT16: 4,
    DATA_TYPE_INT32: 5,
    DATA_TYPE_UINT32: 6,
    DATA_TYPE_INT64: 7,
    DATA_TYPE_UINT64: 8,
    DATA_TYPE_FLOAT: 9,
    DATA_TYPE_DOUBLE: 10,
    DATA_TYPE_STRING: 11,
    DATA_TYPE_INT8_ARRAY: 12,
    DATA_TYPE_UINT8_ARRAY: 13,
    DATA_TYPE_INT16_ARRAY: 14,
    DATA_TYPE_UINT16_ARRAY: 15,
    DATA_TYPE_INT32_ARRAY: 16,
    DATA_TYPE_UINT32_ARRAY: 17,
    DATA_TYPE_INT64_ARRAY: 18,
    DATA_TYPE_UINT64_ARRAY: 19,
    DATA_TYPE_FLOAT_ARRAY: 20,
    DATA_TYPE_DOUBLE_ARRAY: 21,
    DATA_TYPE_STRING_ARRAY: 22,
};
const HEADER_TYPES = {
    OM_HEADER_INVALID: 0,
    OM_HEADER_LEGACY: 1,
    OM_HEADER_READ_TRAILER: 2,
};
const ERROR_CODES = {
    ERROR_OK: 0,
};
// Size of the decoder structure
const SIZEOF_DECODER = 104;
let wasmModuleWrapped = null;
async function initWasm() {
    if (wasmModuleWrapped)
        return wasmModuleWrapped;
    try {
        const OmFileFormat = await import('@openmeteo/file-format-wasm');
        const wasmModuleRaw = await OmFileFormat.default();
        // Create wrapped module with the expected interface
        wasmModuleWrapped = createWrappedModule(wasmModuleRaw);
        return wasmModuleWrapped;
    }
    catch (error) {
        throw new Error("Failed to initialize WASM module", {
            cause: error,
        });
    }
}
function createWrappedModule(rawModule) {
    return {
        // Memory management functions
        _malloc: rawModule._malloc,
        _free: rawModule._free,
        setValue: rawModule.setValue,
        getValue: rawModule.getValue,
        HEAPU8: rawModule.HEAPU8,
        // Map all the C functions to their prefixed versions
        om_header_size: rawModule._om_header_size,
        om_header_type: rawModule._om_header_type,
        om_trailer_size: rawModule._om_trailer_size,
        om_trailer_read: rawModule._om_trailer_read,
        om_variable_init: rawModule._om_variable_init,
        om_variable_get_type: rawModule._om_variable_get_type,
        om_variable_get_compression: rawModule._om_variable_get_compression,
        om_variable_get_scale_factor: rawModule._om_variable_get_scale_factor,
        om_variable_get_add_offset: rawModule._om_variable_get_add_offset,
        om_variable_get_dimensions_count: rawModule._om_variable_get_dimensions_count,
        om_variable_get_dimensions_ptr: rawModule._om_variable_get_dimensions,
        om_variable_get_chunks_ptr: rawModule._om_variable_get_chunks,
        om_variable_get_name_ptr: rawModule._om_variable_get_name,
        om_variable_get_children_count: rawModule._om_variable_get_children_count,
        om_variable_get_children: rawModule._om_variable_get_children,
        om_variable_get_scalar: rawModule._om_variable_get_scalar,
        om_decoder_init: rawModule._om_decoder_init,
        om_decoder_init_index_read: rawModule._om_decoder_init_index_read,
        om_decoder_init_data_read: rawModule._om_decoder_init_data_read,
        om_decoder_read_buffer_size: rawModule._om_decoder_read_buffer_size,
        om_decoder_next_index_read: rawModule._om_decoder_next_index_read,
        om_decoder_next_data_read: rawModule._om_decoder_next_data_read,
        om_decoder_decode_chunks: rawModule._om_decoder_decode_chunks,
        // Constants
        ...HEADER_TYPES,
        ...ERROR_CODES,
        ...DATA_TYPES,
        // Additional info
        sizeof_decoder: SIZEOF_DECODER,
    };
}
function getWasmModule() {
    if (!wasmModuleWrapped) {
        throw new Error("WASM module not initialized. Call initWasm() first.");
    }
    return wasmModuleWrapped;
}

class OmFileReader {
    backend;
    wasm;
    variable;
    variableDataPtr;
    metadataCache;
    constructor(backend, wasm) {
        this.backend = backend;
        this.wasm = wasm ?? getWasmModule();
        this.variable = null;
        this.variableDataPtr = null;
        this.metadataCache = new Map();
    }
    /**
     * Static factory method to create and initialize an OmFileReader
     */
    static async create(backend) {
        // Make sure WASM is initialized
        const wasm = await initWasm();
        const reader = new OmFileReader(backend, wasm);
        await reader.initialize();
        return reader;
    }
    async initialize() {
        let variableData;
        // First, try to read the trailer
        const trailerSize = this.wasm.om_trailer_size();
        const fileSize = await this.backend.count();
        if (fileSize < trailerSize) {
            throw new Error("File too small to contain trailer");
        }
        if (fileSize >= trailerSize) {
            const trailerOffset = fileSize - trailerSize;
            const trailerPtr = await this._readDataBlock(trailerOffset, trailerSize);
            const offsetPtr = this.wasm._malloc(8); // 64-bit value
            const sizePtr = this.wasm._malloc(8);
            try {
                const success = this.wasm.om_trailer_read(trailerPtr, offsetPtr, sizePtr);
                if (success) {
                    const offset = Number(this.wasm.getValue(offsetPtr, "i64"));
                    const size = Number(this.wasm.getValue(sizePtr, "i64"));
                    variableData = await this.backend.getBytes(offset, size);
                }
            }
            finally {
                this.wasm._free(trailerPtr);
                this.wasm._free(offsetPtr);
                this.wasm._free(sizePtr);
            }
        }
        // Fallback to legacy header if trailer reading fails
        if (!variableData) {
            const headerSize = this.wasm.om_header_size();
            const headerData = await this.backend.getBytes(0, headerSize);
            const headerPtr = this.wasm._malloc(headerData.length);
            this.wasm.HEAPU8.set(headerData, headerPtr);
            try {
                const headerType = this.wasm.om_header_type(headerPtr);
                if (headerType === this.wasm.OM_HEADER_LEGACY) {
                    variableData = headerData;
                }
            }
            finally {
                this.wasm._free(headerPtr);
            }
        }
        if (!variableData) {
            throw new Error("Not a valid OM file");
        }
        // Initialize variable
        const variableDataPtr = this.wasm._malloc(variableData.length);
        this.wasm.HEAPU8.set(variableData, variableDataPtr);
        this.variable = this.wasm.om_variable_init(variableDataPtr);
        if (!this.variable) {
            this.wasm._free(variableDataPtr);
            throw new Error("Failed to initialize variable");
        }
        this.variableDataPtr = variableDataPtr;
        return this;
    }
    // Helper method to convert C strings to JS strings
    _getString(strPtr, strLen) {
        const bytes = this.wasm.HEAPU8.subarray(strPtr, strPtr + strLen);
        return new TextDecoder("utf8").decode(bytes);
    }
    dataType() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        return this.wasm.om_variable_get_type(this.variable);
    }
    compression() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        return this.wasm.om_variable_get_compression(this.variable);
    }
    scaleFactor() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        return this.wasm.om_variable_get_scale_factor(this.variable);
    }
    addOffset() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        return this.wasm.om_variable_get_add_offset(this.variable);
    }
    getDimensions() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        const count = Number(this.wasm.om_variable_get_dimensions_count(this.variable));
        const dimensionsPtr = this.wasm.om_variable_get_dimensions_ptr(this.variable);
        // Create view directly into WASM memory
        const int64View = new BigInt64Array(this.wasm.HEAPU8.buffer, dimensionsPtr, count);
        return Array.from(int64View, (bigIntVal) => Number(bigIntVal));
    }
    getChunkDimensions() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        const count = Number(this.wasm.om_variable_get_dimensions_count(this.variable));
        const chunksPtr = this.wasm.om_variable_get_chunks_ptr(this.variable);
        // Create view directly into WASM memory
        const int64View = new BigInt64Array(this.wasm.HEAPU8.buffer, chunksPtr, count);
        return Array.from(int64View, (bigIntVal) => Number(bigIntVal));
    }
    getName() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        // string length is i16
        const lengthPtr = this.wasm._malloc(2);
        const valuePtr = this.wasm.om_variable_get_name_ptr(this.variable, lengthPtr);
        const size = this.wasm.getValue(lengthPtr, "i16");
        this.wasm._free(lengthPtr);
        if (size === 0 || valuePtr === 0) {
            return null;
        }
        return this._getString(valuePtr, size);
    }
    numberOfChildren() {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        return this.wasm.om_variable_get_children_count(this.variable);
    }
    async getChild(index) {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        // Allocate memory for the output parameters
        const offsetPtr = this.wasm._malloc(8);
        const sizePtr = this.wasm._malloc(8);
        const success = this.wasm.om_variable_get_children(this.variable, index, 1, offsetPtr, sizePtr);
        if (!success) {
            this.wasm._free(offsetPtr);
            this.wasm._free(sizePtr);
            return null;
        }
        const offset = Number(this.wasm.getValue(offsetPtr, "i64"));
        const size = Number(this.wasm.getValue(sizePtr, "i64"));
        this.wasm._free(offsetPtr);
        this.wasm._free(sizePtr);
        return this.initChildFromOffsetSize({ offset, size });
    }
    /**
     * Searches direct children by name. Does not search recursively.
     */
    async getChildByName(name) {
        // Check cache first
        const cachedMetadata = this.metadataCache.get(name);
        if (cachedMetadata === null) {
            return null;
        }
        if (cachedMetadata) {
            return await this.initChildFromOffsetSize(cachedMetadata);
        }
        // Search through children and cache metadata
        const numChildren = this.numberOfChildren();
        for (let i = 0; i < numChildren; i++) {
            const metadata = this._getChildMetadata(i);
            if (metadata) {
                const child = await this.initChildFromOffsetSize(metadata);
                const childName = child.getName();
                if (childName) {
                    this.metadataCache.set(childName, metadata);
                    if (childName === name) {
                        return child; // keep this one
                    }
                }
                child.dispose();
            }
        }
        // also remember invalid names
        this.metadataCache.set(name, null);
        return null;
    }
    async initChildFromOffsetSize(offsetSize) {
        const childDataPtr = await this._readDataBlock(offsetSize.offset, offsetSize.size);
        const childReader = new OmFileReader(this.backend, this.wasm);
        childReader.variable = this.wasm.om_variable_init(childDataPtr);
        childReader.variableDataPtr = childDataPtr;
        return childReader;
    }
    /**
     * Get child metadata by index.
     */
    _getChildMetadata(index) {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        // Allocate memory for the output parameters
        const offsetPtr = this.wasm._malloc(8);
        const sizePtr = this.wasm._malloc(8);
        const success = this.wasm.om_variable_get_children(this.variable, index, 1, offsetPtr, sizePtr);
        if (!success) {
            this.wasm._free(offsetPtr);
            this.wasm._free(sizePtr);
            return null;
        }
        const offset = Number(this.wasm.getValue(offsetPtr, "i64"));
        const size = Number(this.wasm.getValue(sizePtr, "i64"));
        this.wasm._free(offsetPtr);
        this.wasm._free(sizePtr);
        return { offset, size };
    }
    /**
     * Find a variable by its path (e.g., "parent/child/grandchild")
     */
    async findByPath(path) {
        const parts = path.split("/").filter((s) => s.length > 0);
        return await this.navigatePath(parts);
    }
    /**
     * Navigate through a path recursively
     */
    async navigatePath(parts) {
        if (parts.length === 0) {
            return null;
        }
        const child = await this.getChildByName(parts[0]);
        if (child) {
            if (parts.length === 1) {
                return child;
            }
            else {
                return await child.navigatePath(parts.slice(1));
            }
        }
        return null;
    }
    // Method to read scalar values
    readScalar(dataType) {
        if (this.variable === null)
            throw new Error("Reader not initialized");
        if (this.dataType() !== dataType.valueOf()) {
            return null;
        }
        // Allocate memory for output parameters
        const ptrPtr = this.wasm._malloc(4); // pointer to pointer
        const sizePtr = this.wasm._malloc(8); // u64
        try {
            const error = this.wasm.om_variable_get_scalar(this.variable, ptrPtr, sizePtr);
            if (error !== this.wasm.ERROR_OK) {
                return null;
            }
            const dataPtr = this.wasm.getValue(ptrPtr, "*");
            if (dataPtr === 0) {
                return null;
            }
            // Read data based on type
            let result;
            // TODO: Support Int64 and Uint64
            switch (dataType) {
                case OmDataType.Int8:
                    result = this.wasm.getValue(dataPtr, "i8");
                    break;
                case OmDataType.Uint8:
                    result = (this.wasm.getValue(dataPtr, "i8") & 0xff);
                    break;
                case OmDataType.Int16:
                    result = this.wasm.getValue(dataPtr, "i16");
                    break;
                case OmDataType.Uint16:
                    result = (this.wasm.getValue(dataPtr, "i16") & 0xffff);
                    break;
                case OmDataType.Int32:
                    result = this.wasm.getValue(dataPtr, "i32");
                    break;
                case OmDataType.Uint32:
                    result = (this.wasm.getValue(dataPtr, "i32") >>> 0);
                    break;
                case OmDataType.Int64:
                    result = this.wasm.getValue(dataPtr, "i64");
                    break;
                case OmDataType.Uint64:
                    // convert to unsigned BigInt
                    {
                        const val = this.wasm.getValue(dataPtr, "i64");
                        result = (val & BigInt("0xFFFFFFFFFFFFFFFF"));
                    }
                    break;
                case OmDataType.Float:
                    result = this.wasm.getValue(dataPtr, "float");
                    break;
                case OmDataType.Double:
                    result = this.wasm.getValue(dataPtr, "double");
                    break;
                case OmDataType.String:
                    {
                        const size = Number(this.wasm.getValue(sizePtr, "i64"));
                        if (size === 0) {
                            return null;
                        }
                        result = this._getString(dataPtr, size);
                    }
                    break;
                default:
                    result = null;
            }
            return result;
        }
        finally {
            this.wasm._free(ptrPtr);
            this.wasm._free(sizePtr);
        }
    }
    newIndexRead(decoderPtr) {
        // Size of OmDecoder_indexRead_t
        const sizeOfRange = 16; // 8 bytes for lowerBound + 8 bytes for upperBound
        const sizeOfIndexRead = 8 + 8 + sizeOfRange * 3; // offset + count + 3 range structs
        // Allocate the memory
        const indexReadPtr = this.wasm._malloc(sizeOfIndexRead);
        this.wasm.om_decoder_init_index_read(decoderPtr, indexReadPtr);
        return indexReadPtr;
    }
    newDataRead(indexReadPtr) {
        // Size of OmDecoder_dataRead_t
        const sizeOfRange = 16; // 8 bytes for lowerBound + 8 bytes for upperBound
        const sizeOfDataRead = 8 + 8 + sizeOfRange * 3; // offset + count + 3 range structs
        // Allocate the memory
        const dataReadPtr = this.wasm._malloc(sizeOfDataRead);
        this.wasm.om_decoder_init_data_read(dataReadPtr, indexReadPtr);
        return dataReadPtr;
    }
    allocateTypedArray(dataType, size, useSharedBuffer = false) {
        if (useSharedBuffer && typeof SharedArrayBuffer === "undefined") {
            throw new Error("SharedArrayBuffer is not available in this environment");
        }
        // Type-safe mapping of data types to their constructors and byte sizes
        const typeInfo = {
            [this.wasm.DATA_TYPE_INT8_ARRAY]: { constructor: (Int8Array), bytes: 1 },
            [this.wasm.DATA_TYPE_UINT8_ARRAY]: { constructor: (Uint8Array), bytes: 1 },
            [this.wasm.DATA_TYPE_INT16_ARRAY]: { constructor: (Int16Array), bytes: 2 },
            [this.wasm.DATA_TYPE_UINT16_ARRAY]: { constructor: (Uint16Array), bytes: 2 },
            [this.wasm.DATA_TYPE_INT32_ARRAY]: { constructor: (Int32Array), bytes: 4 },
            [this.wasm.DATA_TYPE_UINT32_ARRAY]: { constructor: (Uint32Array), bytes: 4 },
            [this.wasm.DATA_TYPE_INT64_ARRAY]: { constructor: (BigInt64Array), bytes: 8 },
            [this.wasm.DATA_TYPE_UINT64_ARRAY]: { constructor: (BigUint64Array), bytes: 8 },
            [this.wasm.DATA_TYPE_FLOAT_ARRAY]: { constructor: (Float32Array), bytes: 4 },
            [this.wasm.DATA_TYPE_DOUBLE_ARRAY]: { constructor: (Float64Array), bytes: 8 },
        };
        const info = typeInfo[dataType];
        const byteLength = size * info.bytes;
        if (useSharedBuffer) {
            // In browsers, crossOriginIsolated must be true; in Node, it's undefined (so skip check)
            if (typeof SharedArrayBuffer === "undefined" ||
                (typeof crossOriginIsolated !== "undefined" && !crossOriginIsolated)) {
                throw new Error("SharedArrayBuffer is not available in this environment");
            }
            const sharedBuffer = new SharedArrayBuffer(byteLength);
            return new info.constructor(sharedBuffer);
        }
        else {
            const normalBuffer = new ArrayBuffer(byteLength);
            return new info.constructor(normalBuffer);
        }
    }
    /**
     * Reads data from the file and returns a new TypedArray of the requested type.
     *
     * @param options Options for reading, including:
     *   - type: The data type to read.
     *   - ranges: Array of dimension ranges to read.
     *   - prefetch: Whether to prefetch data (default: true).
     *   - intoSAB: Use SharedArrayBuffer for output (default: false).
     *   - ioSizeMax: Maximum I/O size (default: 65536).
     *   - ioSizeMerge: Merge threshold for I/O operations (default: 2048).
     */
    async read(options) {
        const { type, ranges, prefetch = true, prefetchConcurrency = 10, intoSAB = false, ioSizeMax = BigInt(65536), ioSizeMerge = BigInt(2048), signal, } = options;
        // Calculate output dimensions
        const outDims = ranges.map((range) => Number(range.end - range.start));
        const totalSize = outDims.reduce((a, b) => a * b, 1);
        const output = this.allocateTypedArray(type, totalSize, intoSAB);
        await this.readInto({ type, output, ranges, ioSizeMax, ioSizeMerge, prefetch, prefetchConcurrency, signal });
        return output;
    }
    /**
     * Reads data into an existing TypedArray with specified dimension ranges.
     *
     * @param options Options for reading, including:
     *   - type: The data type to read.
     *   - output: The TypedArray to read data into.
     *   - ranges: Array of dimension ranges to read.
     *   - prefetch: Whether to prefetch data (default: true).
     *   - ioSizeMax: Maximum I/O size (default: 65536).
     *   - ioSizeMerge: Merge threshold for I/O operations (default: 2048).
     */
    async readInto(options) {
        const { type, output, ranges, prefetch = true, prefetchConcurrency = 10, ioSizeMax = BigInt(65536), ioSizeMerge = BigInt(2048), signal, } = options;
        if (this.dataType() !== type) {
            throw new Error(`Invalid data type: expected ${this.dataType()}, got ${type}`);
        }
        const nDims = ranges.length;
        const fileDims = this.getDimensions();
        // Validate dimension counts
        if (fileDims.length !== nDims) {
            throw new Error(`Mismatched dimensions: file has ${fileDims.length}, request has ${nDims}`);
        }
        // Verify output size before starting
        const totalElements = ranges.reduce((acc, r) => acc * Number(r.end - r.start), 1);
        if (output.length < totalElements) {
            throw new Error(`Output array is too small: needs ${totalElements} elements, has ${output.length}`);
        }
        await this._runWithDecoder(ranges, ioSizeMax, ioSizeMerge, async (decoderPtr) => {
            if (prefetch) {
                await this.decodePrefetch(decoderPtr, prefetchConcurrency, signal);
            }
            await this.decode(decoderPtr, output, signal);
        }, signal);
    }
    /**
     * Warms up the backend cache by requesting the necessary data blocks
     * without decoding them or copying them to a TypedArray.
     */
    async readPrefetch(options) {
        const { ranges, prefetchConcurrency = 20, ioSizeMax = BigInt(65536), ioSizeMerge = BigInt(2048), signal } = options;
        await this._runWithDecoder(ranges, ioSizeMax, ioSizeMerge, async (decoderPtr) => {
            await this.decodePrefetch(decoderPtr, prefetchConcurrency, signal);
        }, signal);
    }
    async decodePrefetch(decoderPtr, concurrency = 10, signal) {
        if (!this.backend.collectPrefetchTasks)
            return;
        const allTasks = [];
        await this._iterateDataBlocks(decoderPtr, async (dataReadPtr) => {
            const dataOffset = Number(this.wasm.getValue(dataReadPtr, "i64"));
            const dataCount = Number(this.wasm.getValue(dataReadPtr + 8, "i64"));
            const tasks = await this.backend.collectPrefetchTasks(dataOffset, dataCount, signal);
            allTasks.push(...tasks);
        }, signal);
        if (allTasks.length > 0) {
            await runLimited(allTasks, concurrency, signal);
        }
    }
    async decode(decoderPtr, outputArray, signal) {
        const outputPtr = this.wasm._malloc(outputArray.byteLength);
        const chunkBufferSize = Number(this.wasm.om_decoder_read_buffer_size(decoderPtr));
        const chunkBufferPtr = this.wasm._malloc(chunkBufferSize);
        const errorPtr = this.wasm._malloc(4); // Separate error ptr for the decode step
        this.wasm.setValue(errorPtr, this.wasm.ERROR_OK, "i32");
        try {
            await this._iterateDataBlocks(decoderPtr, async (dataReadPtr) => {
                const dataOffset = Number(this.wasm.getValue(dataReadPtr, "i64"));
                const dataCount = Number(this.wasm.getValue(dataReadPtr + 8, "i64"));
                const chunkIndexPtr = dataReadPtr + 32; // offset(8), count(8), indexRange(16)
                // Get the compressed data from the backend
                const dataBlockPtr = await this._readDataBlock(dataOffset, dataCount, signal);
                try {
                    const success = this.wasm.om_decoder_decode_chunks(decoderPtr, chunkIndexPtr, dataBlockPtr, BigInt(dataCount), outputPtr, chunkBufferPtr, errorPtr);
                    if (!success) {
                        throw new Error(`Decoder failed: error ${this.wasm.getValue(errorPtr, "i32")}`);
                    }
                }
                finally {
                    this.wasm._free(dataBlockPtr);
                }
            }, signal);
            this.copyToTypedArray(outputPtr, outputArray);
        }
        finally {
            this.wasm._free(errorPtr);
            this.wasm._free(chunkBufferPtr);
            this.wasm._free(outputPtr);
        }
    }
    /**
     * Internal helper to set up the decoder and execute a task.
     * Handles memory allocation and cleanup for ranges and the decoder.
     */
    async _runWithDecoder(ranges, ioSizeMax, ioSizeMerge, task, signal) {
        throwIfAborted(signal);
        if (this.variable === null)
            throw new Error("Reader not initialized");
        const nDims = ranges.length;
        const fileDims = this.getDimensions();
        if (fileDims.length !== nDims) {
            throw new Error(`Mismatched dimensions: file has ${fileDims.length}, request has ${nDims}`);
        }
        const outDims = ranges.map((range) => range.end - range.start);
        // Allocate memory for dimension arrays
        const readOffsetPtr = this.wasm._malloc(nDims * 8);
        const readCountPtr = this.wasm._malloc(nDims * 8);
        const intoCubeOffsetPtr = this.wasm._malloc(nDims * 8);
        const intoCubeDimensionPtr = this.wasm._malloc(nDims * 8);
        try {
            for (let i = 0; i < nDims; i++) {
                if (ranges[i].start < 0 || ranges[i].end > fileDims[i] || ranges[i].start >= ranges[i].end) {
                    throw new Error(`Invalid range for dimension ${i}: ${JSON.stringify(ranges[i])}`);
                }
                this.wasm.setValue(readOffsetPtr + i * 8, BigInt(ranges[i].start), "i64");
                this.wasm.setValue(readCountPtr + i * 8, BigInt(outDims[i]), "i64");
                this.wasm.setValue(intoCubeOffsetPtr + i * 8, BigInt(0), "i64");
                this.wasm.setValue(intoCubeDimensionPtr + i * 8, BigInt(outDims[i]), "i64");
            }
            const decoderPtr = this.wasm._malloc(this.wasm.sizeof_decoder);
            try {
                const error = this.wasm.om_decoder_init(decoderPtr, this.variable, BigInt(nDims), readOffsetPtr, readCountPtr, intoCubeOffsetPtr, intoCubeDimensionPtr, ioSizeMerge, ioSizeMax);
                if (error !== this.wasm.ERROR_OK) {
                    throw new Error(`Decoder initialization failed: error code ${error}`);
                }
                // Run the specific work (decode or prefetch)
                await task(decoderPtr);
            }
            finally {
                this.wasm._free(decoderPtr);
            }
        }
        finally {
            this.wasm._free(readOffsetPtr);
            this.wasm._free(readCountPtr);
            this.wasm._free(intoCubeOffsetPtr);
            this.wasm._free(intoCubeDimensionPtr);
        }
    }
    async _iterateDataBlocks(decoderPtr, callback, signal) {
        const errorPtr = this.wasm._malloc(4);
        this.wasm.setValue(errorPtr, this.wasm.ERROR_OK, "i32");
        const indexReadPtr = this.newIndexRead(decoderPtr);
        try {
            // Loop over index blocks
            while (this.wasm.om_decoder_next_index_read(decoderPtr, indexReadPtr)) {
                throwIfAborted(signal);
                const indexOffset = Number(this.wasm.getValue(indexReadPtr, "i64"));
                const indexCount = Number(this.wasm.getValue(indexReadPtr + 8, "i64"));
                // Get bytes for index-read
                const indexDataPtr = await this._readDataBlock(indexOffset, indexCount, signal);
                const dataReadPtr = this.newDataRead(indexReadPtr);
                try {
                    // Loop over data blocks described by this index block
                    while (this.wasm.om_decoder_next_data_read(decoderPtr, dataReadPtr, indexDataPtr, BigInt(indexCount), errorPtr)) {
                        throwIfAborted(signal);
                        await callback(dataReadPtr, indexDataPtr, BigInt(indexCount));
                    }
                    // Check for errors after the data_read loop finishes for this index block
                    const error = this.wasm.getValue(errorPtr, "i32");
                    if (error !== this.wasm.ERROR_OK) {
                        throw new Error(`Data read iteration error: ${error}`);
                    }
                }
                finally {
                    this.wasm._free(dataReadPtr);
                    this.wasm._free(indexDataPtr);
                }
            }
        }
        finally {
            this.wasm._free(indexReadPtr);
            this.wasm._free(errorPtr);
        }
    }
    async _readDataBlock(offset, size, signal) {
        const data = await this.backend.getBytes(offset, size, signal);
        const ptr = this.wasm._malloc(data.length);
        this.wasm.HEAPU8.set(data, ptr);
        return ptr;
    }
    /**
     * Helper method to copy data from WASM memory to a TypedArray with the correct type
     */
    copyToTypedArray(sourcePtr, targetArray) {
        switch (targetArray.constructor) {
            case Float32Array:
                targetArray.set(new Float32Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case Float64Array:
                targetArray.set(new Float64Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case Int8Array:
                targetArray.set(new Int8Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case Uint8Array:
                targetArray.set(new Uint8Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case Int16Array:
                targetArray.set(new Int16Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case Uint16Array:
                targetArray.set(new Uint16Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case Int32Array:
                targetArray.set(new Int32Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case Uint32Array:
                targetArray.set(new Uint32Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case BigInt64Array:
                targetArray.set(new BigInt64Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            case BigUint64Array:
                targetArray.set(new BigUint64Array(this.wasm.HEAPU8.buffer, sourcePtr, targetArray.length));
                break;
            default:
                throw new Error("Unsupported TypedArray type in copyToTypedArray");
        }
    }
    // Clean up resources when done
    dispose() {
        if (this.variableDataPtr !== null) {
            this.wasm._free(this.variableDataPtr);
            this.variableDataPtr = null;
        }
        this.variable = null;
    }
}

class FileBackend {
    fileObj = null;
    memory = null;
    fileSize = 0;
    constructor(source) {
        if (typeof File !== "undefined" && source instanceof File) {
            this.fileObj = source;
            this.fileSize = source.size;
        }
        else if (typeof Blob !== "undefined" && source instanceof Blob) {
            this.fileObj = source;
            this.fileSize = source.size;
        }
        else if (source instanceof ArrayBuffer) {
            this.memory = new Uint8Array(source);
            this.fileSize = this.memory.length;
        }
        else if (source instanceof Uint8Array) {
            this.memory = source;
            this.fileSize = source.length;
        }
        else {
            throw new Error("Unsupported file source type for browser FileBackend");
        }
    }
    async count() {
        return Promise.resolve(this.fileSize);
    }
    async getBytes(offset, size) {
        if (this.memory) {
            return this.memory.slice(offset, offset + size);
        }
        if (this.fileObj) {
            const blob = this.fileObj.slice(offset, offset + size);
            const buffer = await blob.arrayBuffer();
            return new Uint8Array(buffer);
        }
        throw new Error("No file or memory buffer available");
    }
    // No collectPrefetchTasks - prefetching has minor effect
    async close() {
        // Nothing to clean up in browser
    }
}

class MemoryHttpBackend {
    url;
    fileSize = null;
    fileData = null;
    loadPromise = null;
    countPromise = null;
    maxFileSize;
    onProgress;
    debug;
    /**
     * Create a new MemoryHttpBackend
     * @param options Configuration options
     */
    constructor(options) {
        this.url = options.url;
        this.maxFileSize = options.maxFileSize ?? 200 * 1024 * 1024; // 200 MB default
        this.onProgress = options.onProgress;
        this.debug = options.debug ?? false;
        // Start loading the file in the background
        this.loadFile().catch((err) => {
            if (this.debug)
                console.error("Background file load failed:", err);
        });
    }
    /**
     * Get the total size of the file
     */
    async count() {
        if (this.fileSize !== null) {
            return this.fileSize;
        }
        if (!this.countPromise) {
            if (this.debug)
                console.log(`Making HEAD request to ${this.url}`);
            this.countPromise = (async () => {
                try {
                    const response = await fetch(this.url, {
                        method: "HEAD",
                    });
                    if (!response.ok) {
                        throw new Error(`HTTP error: ${response.status}`);
                    }
                    const contentLength = response.headers.get("content-length");
                    if (!contentLength) {
                        throw new Error("Content-Length header not available");
                    }
                    this.fileSize = parseInt(contentLength, 10);
                    if (this.fileSize > this.maxFileSize) {
                        throw new Error(`File size (${this.fileSize} bytes) exceeds maximum allowed size (${this.maxFileSize} bytes)`);
                    }
                    if (this.debug)
                        console.log(`File size: ${this.fileSize} bytes`);
                    return this.fileSize;
                }
                catch (error) {
                    this.countPromise = null;
                    throw new Error("Failed to get file size", {
                        cause: error,
                    });
                }
            })();
        }
        return this.countPromise;
    }
    /**
     * Load the entire file into memory
     */
    async loadFile() {
        // If already loaded or loading, return that promise
        if (this.fileData) {
            return Promise.resolve();
        }
        if (this.loadPromise) {
            return this.loadPromise;
        }
        this.loadPromise = (async () => {
            try {
                // First get the file size
                const size = await this.count();
                if (this.debug)
                    console.log(`Fetching entire file (${size} bytes) from ${this.url}`);
                // Use fetch with streaming and progress tracking
                const response = await fetch(this.url);
                if (!response.ok) {
                    throw new Error(`HTTP error: ${response.status}`);
                }
                // Check if ReadableStream is supported and if progress tracking is needed
                if (this.onProgress && response.body && "getReader" in response.body) {
                    // Stream the response with progress tracking
                    const contentLength = Number(response.headers.get("content-length") ?? size);
                    const reader = response.body.getReader();
                    const chunks = [];
                    let receivedLength = 0;
                    let lastProgressUpdate = 0;
                    for (;;) {
                        const { done, value } = await reader.read();
                        if (done) {
                            break;
                        }
                        chunks.push(value);
                        receivedLength += value.length;
                        // Don't update progress too frequently (throttle updates)
                        const now = Date.now();
                        if (now - lastProgressUpdate > 100) {
                            // update every 100ms
                            this.onProgress(receivedLength, contentLength);
                            lastProgressUpdate = now;
                        }
                    }
                    // Concatenate chunks into a single Uint8Array
                    this.fileData = new Uint8Array(receivedLength);
                    let position = 0;
                    for (const chunk of chunks) {
                        this.fileData.set(chunk, position);
                        position += chunk.length;
                    }
                    // Final progress update
                    this.onProgress(receivedLength, contentLength);
                }
                else {
                    // Simple approach without streaming
                    const buffer = await response.arrayBuffer();
                    this.fileData = new Uint8Array(buffer);
                    if (this.onProgress) {
                        this.onProgress(this.fileData.length, size);
                    }
                }
                if (this.debug)
                    console.log(`File loaded successfully (${this.fileData.length} bytes)`);
                return;
            }
            catch (error) {
                this.loadPromise = null;
                throw new Error("Failed to load file", {
                    cause: error,
                });
            }
        })();
        return this.loadPromise;
    }
    /**
     * Get bytes from the file
     * @param offset The starting position in the file
     * @param size The number of bytes to read
     */
    async getBytes(offset, size) {
        try {
            // Make sure the file is loaded
            if (!this.fileData) {
                if (this.debug)
                    console.log(`getBytes(${offset}, ${size}): Waiting for file to load...`);
                await this.loadFile();
                if (this.debug)
                    console.log(`getBytes(${offset}, ${size}): File loaded`);
            }
            // At this point, fileData should be available
            if (!this.fileData) {
                throw new Error("File data is not available after load");
            }
            // Bounds check
            if (offset < 0 || offset + size > this.fileData.length) {
                throw new Error(`Requested range (${offset}:${offset + size}) is out of bounds (0:${this.fileData.length})`);
            }
            if (this.debug)
                console.log(`Serving ${size} bytes from offset ${offset} from memory`);
            // Return the requested slice of data
            return this.fileData.slice(offset, offset + size);
        }
        catch (error) {
            throw new Error("Error in getBytes", {
                cause: error,
            });
        }
    }
    /**
     * Check if the file is fully loaded
     */
    isLoaded() {
        return !!this.fileData;
    }
    /**
     * Get the current loaded data or null if not loaded
     */
    getFileData() {
        return this.fileData;
    }
    /**
     * Force a reload of the file
     */
    async reload() {
        this.fileData = null;
        this.loadPromise = null;
        return this.loadFile();
    }
    // No collectPrefetchTasks - prefetching has minor effect
    /**
     * Close the backend and release any resources
     */
    async close() {
        this.fileData = null;
        this.loadPromise = null;
        return Promise.resolve();
    }
}

/**
 * Wraps a backend for caching blocks of data.
 */
class BlockCacheBackend {
    backend;
    cache;
    baseKey;
    keyBuilder;
    cachedCount = null;
    constructor(backend, cache, baseKey, keyBuilder) {
        this.backend = backend;
        this.cache = cache;
        this.baseKey = baseKey;
        this.keyBuilder = keyBuilder;
    }
    /**
     * Creates a BlockCacheBackend using bigint keys.
     */
    static withBigIntKeys(backend, cache, baseKey) {
        return new BlockCacheBackend(backend, cache, baseKey, (base, blockIdx) => base + BigInt(blockIdx));
    }
    /**
     * Creates a BlockCacheBackend using string keys.
     */
    static withStringKeys(backend, cache, baseKey) {
        return new BlockCacheBackend(backend, cache, baseKey, (base, blockIdx) => `${base}/block/${blockIdx}`);
    }
    /**
     * Generates a unique key for a specific block.
     */
    getBlockKey(blockIdxFromEnd) {
        return this.keyBuilder(this.baseKey, blockIdxFromEnd);
    }
    /**
     * Get the byte range for a block indexed from the end.
     * Block 0 = last blockSize bytes, Block 1 = previous blockSize bytes, etc.
     */
    getBlockRange(blockIdxFromEnd, fileSize) {
        const blockSize = this.cache.blockSize();
        const end = fileSize - blockIdxFromEnd * blockSize;
        const start = Math.max(0, end - blockSize);
        return { start, end };
    }
    /**
     * Get the block index (from end) that contains a given offset.
     */
    getBlockIdxFromEnd(offset, fileSize) {
        const blockSize = this.cache.blockSize();
        // Distance from end of file to end of the byte at offset
        const distanceFromEnd = fileSize - offset - 1;
        return Math.floor(distanceFromEnd / blockSize);
    }
    async count(signal) {
        if (this.cachedCount !== null) {
            return this.cachedCount;
        }
        // check last block, which contains the trailer
        const key = this.getBlockKey(0);
        const cached = await this.cache.size(key);
        if (cached !== undefined) {
            this.cachedCount = cached;
            return cached;
        }
        // Fallback to regular count
        this.cachedCount = await this.backend.count(signal);
        return this.cachedCount;
    }
    /**
     * Reads one block through the cache, which cancels the fetch only once no
     * reader is waiting on it anymore: two variables read from the same file
     * share its index blocks, so one of them being abandoned must not fail the
     * other.
     */
    getBlock(blockIdxFromEnd, fileSize, signal) {
        const { start, end } = this.getBlockRange(blockIdxFromEnd, fileSize);
        const key = this.getBlockKey(blockIdxFromEnd);
        return this.cache.get(key, (fetchSignal) => this.backend.getBytes(start, end - start, fetchSignal), fileSize, signal);
    }
    async getBytes(offset, size, signal) {
        throwIfAborted(signal);
        const fileSize = await this.count(signal);
        const startBlockFromEnd = this.getBlockIdxFromEnd(offset + size - 1, fileSize);
        const endBlockFromEnd = this.getBlockIdxFromEnd(offset, fileSize);
        // Single block fast path
        if (startBlockFromEnd === endBlockFromEnd) {
            const { start: blockStart } = this.getBlockRange(startBlockFromEnd, fileSize);
            const block = await this.getBlock(startBlockFromEnd, fileSize, signal);
            const blockOffset = offset - blockStart;
            return block.subarray(blockOffset, blockOffset + size);
        }
        // Multi-block path - iterate from lowest block index (closest to end) to highest
        const output = new Uint8Array(size);
        const promises = [];
        for (let blockIdxFromEnd = startBlockFromEnd; blockIdxFromEnd <= endBlockFromEnd; blockIdxFromEnd++) {
            const { start: blockStart, end: blockEnd } = this.getBlockRange(blockIdxFromEnd, fileSize);
            promises.push(this.getBlock(blockIdxFromEnd, fileSize, signal).then((block) => {
                const srcStart = Math.max(offset, blockStart) - blockStart;
                const dstStart = Math.max(blockStart, offset) - offset;
                const len = Math.min(blockEnd - blockStart - srcStart, size - dstStart);
                output.set(block.subarray(srcStart, srcStart + len), dstStart);
            }));
        }
        await Promise.all(promises);
        return output;
    }
    /**
     * Collects block fetch tasks for a given range without executing them.
     * Returns an array of functions that, when called, will fetch and cache the block.
     */
    async collectPrefetchTasks(offset, size, signal) {
        throwIfAborted(signal);
        const fileSize = await this.count(signal);
        const startBlockFromEnd = this.getBlockIdxFromEnd(offset + size - 1, fileSize);
        const endBlockFromEnd = this.getBlockIdxFromEnd(offset, fileSize);
        const tasks = [];
        for (let blockIdxFromEnd = startBlockFromEnd; blockIdxFromEnd <= endBlockFromEnd; blockIdxFromEnd++) {
            const { start: blockStart, end: blockEnd } = this.getBlockRange(blockIdxFromEnd, fileSize);
            const key = this.getBlockKey(blockIdxFromEnd);
            tasks.push(async () => {
                await this.cache.prefetch(key, (fetchSignal) => this.backend.getBytes(blockStart, blockEnd - blockStart, fetchSignal), fileSize, signal);
            });
        }
        return tasks;
    }
    async close() {
        await this.backend.close();
    }
}

class OmHttpBackendError extends Error {
    statusCode;
    constructor(message, statusCode) {
        super(message);
        this.statusCode = statusCode;
        this.name = "OmHttpBackendError";
    }
}
/**
 * Backend for reading from HTTP servers with partial read support using Range requests.
 * Checks last modified header and ETag.
 */
class OmHttpBackend {
    url;
    debug;
    timeoutMs;
    retries;
    eTagValidation;
    fileSize = null;
    lastModified = null;
    eTag = null;
    metadataPromise = null;
    constructor(options) {
        this.url = options.url;
        this.debug = options.debug ?? false;
        this.timeoutMs = options.timeoutMs ?? 30000;
        this.retries = options.retries ?? 1;
        this.eTagValidation = options.eTagValidation ?? true;
    }
    /**
     * Returns a bigint cache key for use with LruBlockCache.
     * Uniquely identifies the file based on its URL, ETag, and Last-Modified headers.
     * The ETag is only included if validation is enabled.
     */
    get cacheKeyBigInt() {
        const urlHash = fnv1aHash64(this.url);
        const lastModifiedHash = this.lastModified ? fnv1aHash64(this.lastModified) : 0n;
        // Only include the eTag in the cache key if we are actually validating against it.
        const eTagHash = this.eTag && this.eTagValidation ? fnv1aHash64(this.eTag) : 0n;
        return urlHash ^ eTagHash ^ lastModifiedHash;
    }
    /**
     * Returns a string cache key for use with BrowserBlockCache based on the underlying url.
     * If the upstream resource can change, this cache-key is not safe to use!
     * => Only use for static files!
     */
    get cacheKeyString() {
        return this.url;
    }
    /**
     * Fetch metadata using HEAD request
     */
    async fetchMetadata(signal) {
        if (this.metadataPromise) {
            return this.metadataPromise;
        }
        const metadataPromise = (async () => {
            const response = await fetchRetry(this.url, { method: "HEAD" }, this.timeoutMs, this.retries, signal);
            if (!response.ok) {
                throw new OmHttpBackendError(response.status === 404 ? "File not found" : `HTTP error: ${response.status}`, response.status);
            }
            const contentLength = response.headers.get("content-length");
            if (!contentLength)
                throw new OmHttpBackendError("Content-Length header missing");
            this.fileSize = parseInt(contentLength, 10);
            this.lastModified = response.headers.get("last-modified");
            this.eTag = response.headers.get("etag");
        })();
        this.metadataPromise = metadataPromise;
        // A failed fetch must not stay memoized, otherwise a long-lived backend
        // (e.g. from OmHttpBackendPool) could never retry this URL. The rejection
        // itself still reaches callers via the returned metadataPromise.
        void metadataPromise.catch(() => {
            if (this.metadataPromise === metadataPromise) {
                this.metadataPromise = null;
            }
        });
        return metadataPromise;
    }
    /**
     * Get the total size of the file
     */
    async count(signal) {
        if (this.fileSize !== null) {
            return this.fileSize;
        }
        await this.fetchMetadata(signal);
        return this.fileSize;
    }
    /**
     * Get bytes from the file using Range requests
     */
    async getBytes(offset, size, signal) {
        if (offset < 0 || size <= 0) {
            throw new OmHttpBackendError("Invalid offset or size");
        }
        // Ensure we have metadata
        await this.count(signal);
        if (offset + size > this.fileSize) {
            throw new OmHttpBackendError(`Requested range (${offset}:${offset + size}) exceeds file size (${this.fileSize})`);
        }
        // Prepare request
        const headers = {
            Range: `bytes=${offset}-${offset + size - 1}`,
        };
        if (this.eTagValidation) {
            // Add conditional headers for cache validation
            if (this.lastModified) {
                headers["If-Unmodified-Since"] = this.lastModified;
            }
            if (this.eTag) {
                headers["If-Match"] = this.eTag;
            }
        }
        if (this.debug) {
            console.log(`Getting data range ${offset}-${offset + size - 1} from ${this.url}`);
        }
        const response = await fetchRetry(this.url, { headers }, this.timeoutMs, this.retries, signal);
        const buffer = await response.arrayBuffer();
        const data = new Uint8Array(buffer);
        if (data.length !== size) {
            throw new OmHttpBackendError(`Received ${data.length} bytes, expected ${size}`);
        }
        return data;
    }
    // No collectPrefetchTasks here - use BlockCacheBackend wrapper for prefetching
    async asCachedReader(cache) {
        await this.fetchMetadata();
        switch (cache.keyKind) {
            case "bigint": {
                const cachedBackend = BlockCacheBackend.withBigIntKeys(this, cache, this.cacheKeyBigInt);
                return OmFileReader.create(cachedBackend);
            }
            case "string": {
                const cachedBackend = BlockCacheBackend.withStringKeys(this, cache, this.cacheKeyString);
                return OmFileReader.create(cachedBackend);
            }
            default: {
                const _ = cache.keyKind;
                throw Error(`Unknown key type ${String(_)}`);
            }
        }
    }
    /**
     * Open a cached reader, run `fn` with it and dispose it afterwards.
     *
     * The reader never escapes the callback, so callers hold no reader state:
     * there is no "current file" to mutate and no dispose ordering to get wrong
     * when multiple files are read concurrently.
     */
    async withReader(cache, fn) {
        const reader = await this.asCachedReader(cache);
        try {
            return await fn(reader);
        }
        finally {
            reader.dispose();
        }
    }
    /**
     * Close the backend and release resources
     */
    async close() {
        this.metadataPromise = null;
        this.fileSize = null;
        this.lastModified = null;
        this.eTag = null;
        return Promise.resolve();
    }
}
/**
 * Memoizes one `OmHttpBackend` per URL, so repeated reads of the same file skip
 * the HEAD metadata request (a backend memoizes it internally). Backends hold no
 * wasm resources, so eviction is always safe — an evicted backend still in use by
 * an in-flight read keeps working and is garbage collected afterwards.
 */
class OmHttpBackendPool {
    backends = new Map();
    backendOptions;
    maxBackends;
    constructor(options = {}) {
        this.backendOptions = options.backendOptions ?? {};
        this.maxBackends = options.maxBackends ?? 64;
    }
    /** Get (or create) the memoized backend for a URL and mark it recently used. */
    backend(url) {
        const existing = this.backends.get(url);
        if (existing) {
            // Re-insert to move to the most recently used position
            this.backends.delete(url);
            this.backends.set(url, existing);
            return existing;
        }
        const backend = new OmHttpBackend({ ...this.backendOptions, url });
        this.backends.set(url, backend);
        while (this.backends.size > Math.max(1, this.maxBackends)) {
            const oldest = this.backends.keys().next().value;
            if (oldest === undefined)
                break;
            this.backends.delete(oldest);
        }
        return backend;
    }
    /** Scoped read via the memoized backend for `url` (see `OmHttpBackend.withReader`). */
    withReader(url, cache, fn) {
        return this.backend(url).withReader(cache, fn);
    }
    /** Drop all memoized backends, e.g. to force fresh metadata requests. */
    clear() {
        this.backends.clear();
    }
}

/**
 * Deduplicates concurrent fetches of the same key.
 *
 * A fetch runs under a signal of its own rather than under the signal of
 * whichever caller asked first: every caller waiting on it is counted, one
 * aborting only gives up its own claim, and the fetch is cancelled once the
 * last claim is gone. Two variables read from the same file share its index
 * blocks, so one of them being abandoned would otherwise fail the other.
 *
 * A fetch whose callers have all aborted is no longer joinable even while its
 * rejection is still in flight — the next caller starts a fresh one instead of
 * inheriting a cancellation it did not ask for.
 */
class InflightFetches {
    entries = new Map();
    get size() {
        return this.entries.size;
    }
    clear() {
        this.entries.clear();
    }
    async get(key, fetchFn, signal) {
        throwIfAborted(signal);
        let entry = this.entries.get(key);
        if (!entry) {
            const controller = new AbortController();
            const fresh = { controller, waiting: 0, promise: fetchFn(controller.signal) };
            // Only forget what still belongs to this fetch: a cancelled one can have
            // been replaced by a fresh fetch before it settles
            const forget = () => {
                if (this.entries.get(key) === fresh)
                    this.entries.delete(key);
            };
            void fresh.promise.then(forget, forget);
            this.entries.set(key, fresh);
            entry = fresh;
        }
        return this.join(key, entry, signal);
    }
    async join(key, entry, signal) {
        entry.waiting += 1;
        const release = () => {
            entry.waiting -= 1;
            // A settled fetch has already been forgotten; there is nothing to cancel
            if (entry.waiting > 0 || this.entries.get(key) !== entry)
                return;
            this.entries.delete(key);
            entry.controller.abort();
        };
        if (!signal) {
            try {
                return await entry.promise;
            }
            finally {
                release();
            }
        }
        // Rejects as soon as the caller aborts, even though the fetch itself may
        // carry on for the other callers. `onAbort` is assigned synchronously by
        // the executor.
        let onAbort;
        const abortedByCaller = new Promise((resolve) => {
            onAbort = () => resolve();
            signal.addEventListener("abort", onAbort, { once: true });
        });
        try {
            await Promise.race([entry.promise, abortedByCaller]);
            throwIfAborted(signal);
            return await entry.promise;
        }
        finally {
            signal.removeEventListener("abort", onAbort);
            release();
        }
    }
}

/**
 * A BlockCache implementation that uses the browser's Cache API.
 *
 * Features:
 * - Fast in-memory layer for recently accessed blocks
 * - Size-based eviction with configurable limits
 * - Metadata stored in response headers (no separate metadata cache)
 */
class BrowserBlockCache {
    keyKind = "string";
    _blockSize;
    cacheName;
    inflight = new InflightFetches();
    /** In-memory cache for fast repeated access */
    memCache = new Map();
    /** Timers for automatic memory eviction */
    evictionTimers = new Map();
    /** Time in ms before an unused entry is evicted from memory */
    memCacheTtlMs;
    /** Maximum total bytes for persistent storage */
    maxBytes;
    /** Fraction of cache to clear during eviction */
    evictionFraction;
    /** Lock to prevent concurrent evictions */
    evictionInProgress = null;
    /** Cached reference to the opened Cache object */
    cachePromise = null;
    /** Maximum concurrent fetch operations */
    maxConcurrentFetches;
    /** Currently active fetch count */
    activeFetches = 0;
    /** Queue of pending fetch operations */
    fetchQueue = [];
    constructor(options = {}) {
        // Guard early to make misuse in SSR or non-Cache environments immediate and clear
        if (typeof caches === "undefined") {
            throw new Error("BrowserBlockCache is browser-only. Import it dynamically in the client (e.g. inside onMount()).");
        }
        this._blockSize = options.blockSize ?? 64 * 1024;
        this.cacheName = options.cacheName ?? "om-file-cache";
        this.memCacheTtlMs = options.memCacheTtlMs ?? 1000;
        this.maxBytes = options.maxBytes ?? 1024 * 1024 * 1024; // 1GB default
        this.evictionFraction = options.evictionFraction ?? 0.1;
        this.maxConcurrentFetches = options.maxConcurrentFetches ?? 10;
    }
    blockSize() {
        return this._blockSize;
    }
    async size(key) {
        const cache = await this.getCache();
        if (cache) {
            const url = this.resolveUrl(key);
            const fileSize = (await cache.match(url))?.headers.get("X-Om-File-Size");
            if (fileSize) {
                return parseInt(fileSize, 10);
            }
        }
        return undefined;
    }
    /**
     * Resolves a BlockKey into a URL string for the Cache API.
     */
    resolveUrl(key) {
        const encodedKey = encodeURIComponent(key);
        return `https://omfiles.local/cache/${encodedKey}`;
    }
    /**
     * Acquires a fetch slot. Resolves when a slot is available.
     */
    acquireFetchSlot() {
        if (this.activeFetches < this.maxConcurrentFetches) {
            this.activeFetches++;
            return Promise.resolve();
        }
        return new Promise((resolve) => {
            this.fetchQueue.push(resolve);
        });
    }
    /**
     * Releases a fetch slot and processes the next queued request.
     */
    releaseFetchSlot() {
        const next = this.fetchQueue.shift();
        if (next) {
            // Don't decrement, just hand off to the next waiter
            next();
        }
        else {
            this.activeFetches--;
        }
    }
    /**
     * Executes a fetch function with concurrency limiting.
     */
    async limitedFetch(fetchFn, signal) {
        await this.acquireFetchSlot();
        try {
            throwIfAborted(signal);
            return await fetchFn(signal);
        }
        finally {
            this.releaseFetchSlot();
        }
    }
    /** Opens the cache once and reuses the reference */
    async getCache() {
        if (typeof caches === "undefined")
            return null;
        this.cachePromise ??= caches.open(this.cacheName);
        return this.cachePromise;
    }
    /**
     * Scans the Cache API to get current total size and entry list.
     */
    async scanCache() {
        const cache = await this.getCache();
        if (!cache) {
            return { totalBytes: 0, entries: [] };
        }
        const keys = await cache.keys();
        const entries = [];
        let totalBytes = 0;
        for (const request of keys) {
            const response = await cache.match(request);
            if (response) {
                const size = parseInt(response.headers.get("Content-Length") ?? "0", 10);
                const createdAtStr = response.headers.get("X-Om-Created-At");
                const createdAt = createdAtStr ? parseInt(createdAtStr, 10) : undefined;
                entries.push({
                    url: request.url,
                    size,
                    createdAt,
                });
                totalBytes += size;
            }
        }
        return { totalBytes, entries };
    }
    /**
     * Evicts oldest entries until we're under the size limit.
     * Uses createdAt timestamp from headers for ordering.
     */
    async evictIfNeeded() {
        const cache = await this.getCache();
        if (!cache)
            return;
        // Prevent concurrent evictions
        if (this.evictionInProgress) {
            await this.evictionInProgress;
            return;
        }
        this.evictionInProgress = (async () => {
            const { totalBytes, entries } = await this.scanCache();
            if (totalBytes <= this.maxBytes)
                return;
            const targetBytes = this.maxBytes * (1 - this.evictionFraction);
            let currentBytes = totalBytes;
            // Sort by createdAt (oldest first), entries without timestamp go first
            entries.sort((a, b) => (a.createdAt ?? 0) - (b.createdAt ?? 0));
            for (const entry of entries) {
                if (currentBytes <= targetBytes)
                    break;
                await cache.delete(entry.url).catch((err) => {
                    console.error(`Could not delete from cache: ${err}`);
                });
                currentBytes -= entry.size;
                // Also remove from memory cache
                this.memCache.delete(entry.url);
                const timer = this.evictionTimers.get(entry.url);
                if (timer) {
                    clearTimeout(timer);
                    this.evictionTimers.delete(entry.url);
                }
            }
        })();
        try {
            await this.evictionInProgress;
        }
        finally {
            this.evictionInProgress = null;
        }
    }
    /**
     * Refreshes the memory eviction timer for a URL.
     */
    refreshEvictionTimer(url) {
        const existing = this.evictionTimers.get(url);
        if (existing) {
            clearTimeout(existing);
        }
        const timer = setTimeout(() => {
            this.memCache.delete(url);
            this.evictionTimers.delete(url);
        }, this.memCacheTtlMs);
        this.evictionTimers.set(url, timer);
    }
    /**
     * Stores data in the in-memory cache with automatic eviction.
     */
    setMemCache(url, data) {
        this.memCache.set(url, data);
        this.refreshEvictionTimer(url);
    }
    async get(key, fetchFn, fileSize, signal) {
        throwIfAborted(signal);
        const url = this.resolveUrl(key);
        // Fast path: check in-memory cache first
        const memCached = this.memCache.get(url);
        if (memCached) {
            this.refreshEvictionTimer(url);
            return memCached;
        }
        return this.inflight.get(url, async (fetchSignal) => {
            // Check browser Cache API
            const cache = await this.getCache();
            // Check browser Cache API
            if (cache) {
                const cached = await cache.match(url);
                if (cached) {
                    const buffer = await cached.arrayBuffer();
                    const data = new Uint8Array(buffer);
                    this.setMemCache(url, data);
                    return data;
                }
            }
            // Fetch from source with concurrency limiting
            throwIfAborted(fetchSignal);
            const data = await this.limitedFetch(fetchFn, fetchSignal);
            this.setMemCache(url, data);
            // Store in browser Cache API with metadata in headers
            if (cache) {
                const buffer = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
                const response = new Response(buffer, {
                    status: 200,
                    statusText: "OK",
                    headers: {
                        "Content-Type": "application/octet-stream",
                        "Content-Length": data.length.toString(),
                        "X-Om-Block-Key": key.toString(),
                        "X-Om-Created-At": Date.now().toString(),
                    },
                });
                if (fileSize !== undefined) {
                    response.headers.append("X-Om-File-Size", fileSize.toString());
                }
                cache
                    .put(url, response)
                    .then(() => this.evictIfNeeded())
                    .catch((err) => {
                    console.error(`Could not write to cache: ${err}`);
                });
            }
            return data;
        }, signal);
    }
    async prefetch(key, fetchFn, fileSize, signal) {
        await this.get(key, fetchFn, fileSize, signal).catch(() => {
            // ignore errors during prefetch
        });
    }
    /**
     * Gets current cache statistics by scanning the Cache API.
     */
    async getStats() {
        const { totalBytes, entries } = await this.scanCache();
        let memoryBytes = 0;
        for (const data of this.memCache.values()) {
            memoryBytes += data.length;
        }
        return {
            persistentEntries: entries.length,
            persistentBytes: totalBytes,
            memoryEntries: this.memCache.size,
            memoryBytes,
            inflightCount: this.inflight.size,
            maxBytes: this.maxBytes,
            blockSize: this._blockSize,
        };
    }
    async clear() {
        // Clear all memory eviction timers
        for (const timer of this.evictionTimers.values()) {
            clearTimeout(timer);
        }
        this.evictionTimers.clear();
        this.memCache.clear();
        this.inflight.clear();
        this.cachePromise = null;
        if (typeof caches !== "undefined") {
            await caches.delete(this.cacheName);
        }
    }
}

class LruBlockCache {
    keyKind = "bigint";
    _blockSize;
    maxBlocks;
    cache = new Map();
    inflight = new InflightFetches();
    constructor(blockSize = 64 * 1024, maxBlocks = 256) {
        this._blockSize = blockSize;
        this.maxBlocks = maxBlocks;
    }
    blockSize() {
        return this._blockSize;
    }
    size(_key) {
        return Promise.resolve(undefined);
    }
    async get(key, fetchFn, _fileSize, signal) {
        throwIfAborted(signal);
        // Check cache
        const cached = this.cache.get(key);
        if (cached) {
            // Move to end (LRU refresh) - Map preserves insertion order
            this.cache.delete(key);
            this.cache.set(key, cached);
            return cached;
        }
        return this.inflight.get(key, async (fetchSignal) => {
            const data = await fetchFn(fetchSignal);
            // Evict if needed
            if (this.cache.size >= this.maxBlocks) {
                const oldest = this.cache.keys().next().value;
                if (oldest !== undefined)
                    this.cache.delete(oldest);
            }
            this.cache.set(key, data);
            return data;
        }, signal);
    }
    async prefetch(key, fetchFn, fileSize, signal) {
        await this.get(key, fetchFn, fileSize, signal).catch(() => {
            // ignore errors during prefetch
        });
    }
    clear() {
        this.cache.clear();
        this.inflight.clear();
    }
}

export { BlockCacheBackend, BrowserBlockCache, CompressionType, FileBackend, LruBlockCache, MemoryHttpBackend, OmDataType, OmFileReader, OmHttpBackend, OmHttpBackendPool, getWasmModule, initWasm };
//# sourceMappingURL=index.browser.js.map
