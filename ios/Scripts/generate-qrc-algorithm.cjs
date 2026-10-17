const fs = require('node:fs');
const { stripTypeScriptTypes } = require('node:module');
// ios/Scripts/generate-qrc-algorithm.cjs — preserve Folia's exact custom DES tables in native JavaScriptCore.
const source = fs.readFileSync('src/utils/lyrics/providers/qrcDecrypt.ts', 'utf8');
const pure = source.slice(0, source.indexOf('/**\n * Helper to decompress'));
const js = stripTypeScriptTypes(pure) + '\nglobalThis.decryptArray = function(values) { const key = Uint8Array.from(Array.from("!@#)(*$%123ZXC!@!@#)(NHL",c=>c.charCodeAt(0))); const bytes=Uint8Array.from(values);const schedule=tripledes_key_setup(key,0);const output=new Uint8Array(bytes.length);for(let i=0;i<bytes.length;i+=8){const block=new Uint8Array(8);block.set(bytes.subarray(i,i+8));output.set(tripledes_crypt(block,schedule).subarray(0,Math.min(8,bytes.length-i)),i);}return Array.from(output);};';
const literal = JSON.stringify(js).replaceAll('\\/', '/');
fs.writeFileSync('ios/Folia/Services/QRCAlgorithm.swift', 'import Foundation\n// ios/Folia/Services/QRCAlgorithm.swift — generated from existing Folia qrcDecrypt.ts; regenerate with ios/Scripts/generate-qrc-algorithm.cjs.\n\nenum QRCAlgorithm {\n    static let script = ' + literal + '\n}\n');
