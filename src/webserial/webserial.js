mergeInto(LibraryManager.library, {
  webserial_read: function (bufferPtr, length) {
    return Asyncify.handleAsync(async () => {
      try {
        const { value, done } = await Module.reader.read();
        if (done) {
          Module.reader.releaseLock();
          return 0;
        }
        const buffer = new Uint8Array(Module.HEAPU8.buffer, bufferPtr, length);
        const bytesToCopy = Math.min(value.length, length);
        buffer.set(value.slice(0, bytesToCopy));
        return bytesToCopy;
      } catch (e) {
        console.error('Error reading from serial port:', e);
        return 0;
      }
    });
  },

  webserial_write: function (bufferPtr, length) {
    return Asyncify.handleAsync(async () => {
      try {
        const data = new Uint8Array(Module.HEAPU8.buffer, bufferPtr, length);
        await Module.writer.write(data);
        return length;
      } catch (e) {
        console.error('Error writing to serial port:', e);
        return 0;
      }
    });
  },
});
