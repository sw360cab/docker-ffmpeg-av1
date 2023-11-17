import fsPromise from 'node:fs/promises';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { videoTranscode, 
  H264_VIDEO_CODEC, HEVC_VIDEO_CODEC, AOM_AV1_VIDEO_CODEC } from './lib/ffmpeg-transcoder.js';

const OUTPUT_FOLDER_NAME = "out";
const OUTPUT_FILE_EXT = ".mp4";

const VALID_CODECS = {
  "av1": AOM_AV1_VIDEO_CODEC,
  "h264": H264_VIDEO_CODEC,
  "hevc": HEVC_VIDEO_CODEC
}

// Gather file base name without extension
const baseNameNoExt = (filePath) => {
  return path.basename(filePath, path.extname(filePath));
}

const getOutputFolderPath = (filePath, codec, outputFolder=OUTPUT_FOLDER_NAME) => {
  const outputFolderPath = path.join(path.dirname(filePath), outputFolder, codec);
  return fsPromise.mkdir(outputFolderPath, {recursive:true})
  .then( _ => { return outputFolderPath })
  .catch(e => {
    process.stdout.write(["Unable to create output folder",outputFolderPath,e].join(" "));
    process.exit(1);
  });
}

const main = () => {
  const {
    values: { input, codec },
  } = parseArgs({
    options: {
      input: {
        type: "string",
        short: "i",
      },
      codec: {
        type: "string",
        short: "c",
      },
    },
    strict: true
  });

  if (codec === undefined || input === undefined) {
    process.stdout.write("Missing required parameter 'input'[input file] and 'codec'[video codec: {" +
      Object.keys(VALID_CODECS).join(", ") + "}]");
    process.exit(1);
  }
  
  if (codec.indexOf[Object.keys(VALID_CODECS)] < 0) {
    process.stdout.write("Invalid codec provided. Valid codecs are: " +
      Object.keys(VALID_CODECS).join(", "));
    process.exit(1);
  }

  return getOutputFolderPath(input, codec)
  .then( (outputFolder) => {
    videoTranscode(input,
      path.join(outputFolder, baseNameNoExt(input) + OUTPUT_FILE_EXT),
      VALID_CODECS[codec]);
  })
}
main();

