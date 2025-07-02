/// .Destroy()
/// 
/// .FromBuffer(buffer)
/// 
/// .CopyFromBuffer(buffer)
/// 
/// .GetBuffer()
/// 
/// .Delete(position, count)
/// 
/// .Insert(position, value, [datatype])
/// 
/// .Overwrite(position, value, [datatype])
/// 
/// .FromString(string, ...)
/// 
/// .GetString()

#macro __BUFFER_BATCH_DELETE     -1
#macro __BUFFER_BATCH_OVERWRITE   0
#macro __BUFFER_BATCH_INSERT      1

function BufferBatch() constructor
{
    __inBuffer  = undefined;
    __outBuffer = undefined;
    __commands  = [];
    
    __inBufferCopied = false;
    
    
    
    static FreeMemory = function()
    {
        if ((__inBuffer != undefined) && __inBufferCopied)
        {
            buffer_delete(__inBuffer);
            __inBuffer = undefined;
        }
        
        if (__outBuffer != undefined)
        {
            buffer_delete(__outBuffer);
            __outBuffer = undefined;
        }
        
        array_resize(__commands, 0);
    }
    
    
    
    #region Ingest
    
    static FromBuffer = function(_buffer)
    {
        if ((__inBuffer != undefined) && __inBufferCopied)
        {
            buffer_delete(__inBuffer);
        }
        
        __inBuffer = _buffer;
        __inBufferCopied = false;
        
        return self;
    }
    
    static CopyFromBuffer = function(_buffer, _start = 0, _count = (buffer_get_size(_buffer) - _start))
    {
        if ((__inBuffer != undefined) && __inBufferCopied)
        {
            buffer_delete(__inBuffer);
        }
        
        __inBuffer = buffer_create(_count, buffer_grow, 1);
        buffer_copy(__inBuffer, _start, _count, _buffer, 0);
        __inBufferCopied = true;
        
        return self;
    }
    
    static FromString = function(_string)
    {
        if ((__inBuffer != undefined) && __inBufferCopied)
        {
            buffer_delete(__inBuffer);
        }
        
        __inBuffer = buffer_create(string_byte_length(_string), buffer_grow, 1);
        buffer_write(__inBuffer, buffer_text, _string);
        __inBufferCopied = true;
        
        return self;
    }
    
    #endregion
    
    
    
    #region Return
    
    static GetString = function()
    {
        GetBuffer();
        
        buffer_seek(__outBuffer, buffer_seek_start, 0);
        return buffer_read(__outBuffer, buffer_text);
    }
    
    static GetBuffer = function()
    {
        if (__outBuffer != undefined)
        {
            buffer_delete(__outBuffer);
            __outBuffer = undefined;
        }
        
        //Early-out if we have no commands set up
        if (array_length(__commands) <= 0)
        {
            __outBuffer = buffer_create(buffer_get_size(__inBuffer), buffer_grow, 1);
            buffer_copy(__inBuffer, 0, buffer_get_size(__inBuffer), __outBuffer, 0);
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
        var _inBuffer   = __inBuffer;
        var _inputSize  = buffer_get_size(_inBuffer);
        var _inputPos   = 0;
        var _outputSize = _inputSize;
        
        var _i = 0;
        repeat(array_length(__commands))
        {
            var _command = __commands[_i];
            var _count   = _command.__count;
            
            switch(_command.__type)
            {
                case __BUFFER_BATCH_DELETE:
                    if (_inputPos + _count > _inputSize)
                    {
                        _count = _inputSize - _inputPos;
                        _command.__countAdjusted = _count;
                    }
                    
                    _outputSize -= _count;
                    _inputPos   += _count;
                break;
                
                case __BUFFER_BATCH_OVERWRITE:
                    _outputSize += max(0, _count - (_inputSize - _inputPos));
                    _inputPos   += _count;
                break;
                
                case __BUFFER_BATCH_INSERT:
                    _outputSize += _count;
                break;
            }
            
            ++_i;
        }
        
        if (_outputSize < 0)
        {
            __outBuffer = buffer_create(0, buffer_grow, 1);
            return __outBuffer;
        }
        
        var _outBuffer = buffer_create(_outputSize, buffer_grow, 1);
        __outBuffer = _outBuffer;
        
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
                
                buffer_copy(_inBuffer, _inputPos, _count, _outBuffer, _outputPos);
                buffer_seek(_outBuffer, buffer_seek_relative, _count);
                
                //Advance both position trackers
                _inputPos  += _count;
                _outputPos += _count;
            }
            
            //Now do some actual work!
            switch(_command.__type)
            {
                case __BUFFER_BATCH_INSERT:
                    buffer_write(_outBuffer, _command.__datatype, _command.__content);
                    _outputPos += _command.__countAdjusted;
                break;
                
                case __BUFFER_BATCH_OVERWRITE:
                    buffer_write(_outBuffer, _command.__datatype, _command.__content);
                    _outputPos += _command.__countAdjusted;
                    _inputPos  += _command.__countAdjusted;
                break;
                
                case __BUFFER_BATCH_DELETE:
                    _inputPos += _command.__countAdjusted;
                break;
            }
            
            ++_i;
        }
        
        //Copy across any remaining data from the input buffer if the last command falls short of the
        //length of the input buffer.
        if (_inputPos < _inputSize)
        {
            buffer_copy(_inBuffer, _inputPos, _inputSize - _inputPos, _outBuffer, _outputPos);
        }
        
        buffer_seek(_outBuffer, buffer_seek_start, 0);
        
        return _outBuffer;
    }
    
    #endregion
    
    
    
    #region Commands
    
    static __CommandClass = function(_type, _position, _datatype, _content, _count) constructor
    {
        __type     = _type;
        __position = _position;
        __datatype = _datatype;
        __count    = _count;
        __content  = _content;
        
        __countAdjusted = _count;
        
        __nth = array_length(other.__commands);
        array_push(other.__commands, self);
    }
    
    static Clear = function()
    {
        array_resize(__commands, 0);
        return self;
    }
    
    static Delete = function(_position, _count)
    {
        new __CommandClass(__BUFFER_BATCH_DELETE, _position, undefined, undefined, _count);
        return self;
    }
    
    static Insert = function(_position, _content, _datatype = undefined)
    {
        __AddCommand(__BUFFER_BATCH_INSERT, _position, _content, _datatype);
        return self;
    }
    
    static Overwrite = function(_position, _content, _datatype = undefined)
    {
        __AddCommand(__BUFFER_BATCH_OVERWRITE, _position, _content, _datatype);
        return self;
    }
    
    static __AddCommand = function(_type, _position, _content, _datatype)
    {
        if (_datatype == undefined)
        {
            if (is_string(_content))
            {
                _datatype = buffer_text;
            }
            else
            {
                __Error($"Datatype must be specified if content is not a string (content datatype={typeof(_content)})");
            }
        }
        
        if (_datatype == buffer_text)
        {
            new __CommandClass(_type, _position, buffer_text, _content, string_byte_length(_content));
        }
        else if (_datatype == buffer_string)
        {
            new __CommandClass(_type, _position, buffer_string, _content, string_byte_length(_content)+1);
        }
        else
        {
            new __CommandClass(_type, _position, _datatype, _content, buffer_sizeof(_datatype));
        }
    }
    
    #endregion
    
    
    
    static __Error = function(_string)
    {
        show_error("BufferBatch:\n" + string(_string) + "\n ", true);
    }
}