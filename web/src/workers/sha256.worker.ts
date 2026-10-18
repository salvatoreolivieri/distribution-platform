/// <reference lib="webworker" />
// Hashes a File off the main thread and posts the base64 SHA-256 that S3 expects in
// x-amz-checksum-sha256. Placeholder: reads the whole file; the streaming version (chunked
// incremental hash) lands with the upload feature.
self.onmessage = async (e: MessageEvent<File>) => {
  const digest = await crypto.subtle.digest('SHA-256', await e.data.arrayBuffer());
  const bytes = new Uint8Array(digest);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  self.postMessage(btoa(binary));
};
