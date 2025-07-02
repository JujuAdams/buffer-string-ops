/// .Destroy()
/// 
/// .FromBuffer(buffer)
/// 
/// .CopyFromBuffer(buffer)
/// 
/// .FromString(string, ...)
/// 
/// .Delete(position, count)
/// 
/// .InsertString(position, string, ...)
/// 
/// .OverwriteString(position, string, ...)
/// 
/// .PrefixString(string, ...)
/// 
/// .SuffixString(string, ...)
/// 
/// .GetString()
/// 
/// .GetBuffer()

function BufferBatch() constructor
{
    __destroyed  = false;
    __inBuffer   = undefined;
    __workBuffer = undefined;
    __outBuffer  = undefined;
    __commands   = [];
    
    
    
    static Destroy = function()
    {
        if (__destroyed) return;
        __destroyed = true;
        
        if (__inBuffer != undefined)
        {
            buffer_delete(__inBuffer);
            __inBuffer = undefined;
        }
        
        if (__workBuffer != undefined)
        {
            buffer_delete(__workBuffer);
            __workBuffer = undefined;
        }
        
        if (__outBuffer != undefined)
        {
            buffer_delete(__outBuffer);
            __outBuffer = undefined;
        }
        
        __commands = undefined;
    }
    
    
    
    #region Return
    
    static GetString = function()
    {
        GetBuffer();
        
        buffer_seek(__outBuffer, buffer_seek_start, 0);
        return buffer_read(__outBuffer, buffer_text);
    }
    
    static GetBuffer = function()
    {
        //Early-out if we have no commands set up
        if (array_length(__commands) <= 0)
        {
            if (__outBuffer == undefined)
            {
                __outBuffer = buffer_create(buffer_get_size(__inBuffer), buffer_grow, 1);
                buffer_copy(__inBuffer, 0, buffer_get_size(__inBuffer), __outBuffer, 0);
            }
            
            return __outBuffer;
        }
        
        //Order commands such that we're travelling from the start of the input buffer to the end
        array_sort(__commands, function(_a, _b)
        {
            var _a_pos = _a.__position;
            var _b_pos = _b.__position;
            
            if (_a_pos != _b_pos)
            {
                return (_a_pos < _b_pos)? -1 : 1;
            }
            
            return (_a.__nth < _b.__nth)? -1 : 1;
        });
        
        //Figure out the final size of the output buffer
        //TODO - Do this as we're adding commands
        //TODO - Do we really need this? A greedy estimate is fine
        var _inputSize  = buffer_get_size(__inBuffer);
        var _inputPos   = 0;
        var _outputSize = _inputSize;
        
        var _i = 0;
        repeat(array_length(__commands))
        {
            var _command = __commands[_i];
            var _count   = _command.__count;
            
            switch(_command.__type)
            {
                case "delete":
                    if (_inputPos + _count > _inputSize)
                    {
                        _count = _inputSize - _inputPos;
                        _command.__countAdjusted = _count;
                    }
                    
                    _outputSize -= _count;
                    _inputPos   += _count;
                break;
                
                case "insert":
                case "prefix":
                case "suffix":
                    _outputSize += _count;
                break;
                
                case "overwrite":
                    _outputSize += max(0, _count - (_inputSize - _inputPos));
                    _inputPos   += _count;
                break;
            }
            
            ++_i;
        }
        
        if (_outputSize < 0)
        {
            __outBuffer = buffer_create(0, buffer_grow, 1);
            return __outBuffer;
        }
        
        __outBuffer = buffer_create(_outputSize, buffer_grow, 1);
        
        var _inputPos  = 0;
        var _outputPos = 0;
        
        var _i = 0;
        repeat(array_length(__commands))
        {
            //Pull the next command from the array
            var _command = __commands[_i];
            var _commandPos = _command.__position;
            
            //Restrict prefix / suffix position
            _commandPos = clamp(_commandPos, 0, _inputSize);
            
            if ((_commandPos > _inputPos) && (_inputPos < _inputSize))
            {
                //Our next command is further along the input buffer. This means we need to copy a chunk of the
                //input buffer to the output buffer to fill in the gap.
                var _count = _commandPos - _inputPos;
                
                buffer_copy(__inBuffer, _inputPos, _count, __outBuffer, _outputPos);
                buffer_seek(__outBuffer, buffer_seek_relative, _count);
                
                //Advance both position trackers
                _inputPos  += _count;
                _outputPos += _count;
            }
            
            //Now do some actual work!
            var _count = _command.__countAdjusted;
            switch(_command.__type)
            {
                case "insert":
                case "prefix":
                case "suffix":
                    buffer_write(__outBuffer, buffer_text, _command.__content);
                    _outputPos += _count;
                break;
                
                case "overwrite":
                    buffer_write(__outBuffer, buffer_text, _command.__content);
                    _inputPos  += _count;
                    _outputPos += _count;
                break;
                
                case "delete":
                    _inputPos += _count;
                break;
            }
            
            ++_i;
        }
        
        //Copy across any remaining data from the input buffer if the last command falls short of the
        //length of the input buffer.
        if (_outputPos < _outputSize)
        {
            buffer_copy(__inBuffer, _inputPos, _outputSize - _outputPos, __outBuffer, _outputPos);
        }
        
        buffer_seek(__outBuffer, buffer_seek_start, 0);
        
        return __outBuffer;
    }
    
    #endregion
    
    
    
    #region Commands
    
    static __CommandClass = function(_type, _position, _content, _count) constructor
    {
        __type     = _type;
        __position = _position;
        __count    = _count;
        __content  = _content;
        
        __countAdjusted = _count;
        
        __nth = array_length(other.__commands);
        array_push(other.__commands, self);
    }
    
    static Delete = function(_position, _count)
    {
        new __CommandClass("delete", _position, undefined, _count);
    }
    
    static InsertString = function(_position, _content)
    {
        new __CommandClass("insert", _position, _content, string_byte_length(_content));
    }
    
    static OverwriteString = function(_position, _content)
    {
        new __CommandClass("overwrite", _position, _content, string_byte_length(_content));
    }
    
    static PrefixString = function(_content)
    {
        new __CommandClass("prefix", -infinity, _content, string_byte_length(_content));
    }
    
    static SuffixString = function(_content)
    {
        new __CommandClass("suffix", infinity, _content, string_byte_length(_content));
    }
    
    #endregion
    
    
    
    #region Ingest
    
    static FromBuffer = function(_buffer)
    {
        if (__inBuffer != undefined) __Error("Input buffer already loaded");
        
        __inBuffer = _buffer;
        buffer_seek(__inBuffer, buffer_seek_start, 0);
        
        return __inBuffer;
    }
    
    static CopyFromBuffer = function(_buffer, _start = 0, _count = (buffer_get_size(_buffer) - _start))
    {
        if (__inBuffer != undefined) __Error("Input buffer already loaded");
        
        __inBuffer = buffer_create(_count, buffer_grow, 1);
        buffer_copy(__inBuffer, _start, _count, _buffer, 0);
        
        return __inBuffer;
    }
    
    static FromString = function(_string)
    {
        if (__inBuffer != undefined) __Error("Input buffer already loaded");
        
        __inBuffer = buffer_create(string_byte_length(_string), buffer_grow, 1);
        buffer_write(__inBuffer, buffer_text, _string);
        
        return __inBuffer;
    }
    
    #endregion
    
    
    
    static __Error = function(_string)
    {
        show_error("BufferBatch:\n" + string(_string) + "\n ", true);
    }
}