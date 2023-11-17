import {spawn} from 'node:child_process';
//-------------------------------------------------------------------------------
// CONFIGURABLE SETTINGS
//-------------------------------------------------------------------------------

// video filters: deinterlace and fast start
// NOTE:-vf/-af/-filter and -filter_complex cannot be used together for the same stream.
const VIDEO_FILTERS="-movflags +faststart";

// ref. https://trac.ffmpeg.org/wiki/Encode/H.264
const H264_VIDEO_CODEC = '-c:v libx264 -pix_fmt yuv420p -profile:v high -level 4.1 -preset slower -crf 25 -tune film';

// ref. https://trac.ffmpeg.org/wiki/Encode/H.264
const HEVC_VIDEO_CODEC = '-c:v libx264 -pix_fmt yuv420p -profile:v main -preset slower -crf 23 -tune film';

// ref. https://trac.ffmpeg.org/wiki/Encode/AV1#SVT-AV1
const AOM_AV1_VIDEO_CODEC = '-c:v libsvtav1 -pix_fmt yuv420p -crf 45 -preset 7 -svtav1-params fast-decode=1:film-grain=7:tune=0';

// ref. https://trac.ffmpeg.org/wiki/Encode/AAC#fdk_aac
const HE_AAC_AUDIO_CODEC = '-c:a libfdk_aac -b:a 128k';

const transcode = (inputFilePath, outputFilePath, args) => {
  return new Promise((resolve,failure) => {
    const start = Date.now();
    console.log(["/usr/local/bin/ffmpeg", ...args].join(' '))
    
    const ffmpeg = spawn("/usr/local/bin/ffmpeg", args);
    ffmpeg.stdout.on('data', (data) => {
      console.log(`stdout: ${data}`);
    });
    ffmpeg.stderr.on('data', (data) => {
      console.error(`stderr: ${data}`);
    });
    ffmpeg.on('close', (code) => {
      if (code == 0) {
        console.log('FFMpeg executed in',(Date.now() - start)/1000, 'sec.');
        return resolve();
      }
      return failure(new Error("FFMPEG exited with code " + code));
    })
    .on('error', function(err) {
      console.log(`Cannot process media "${inputFilePath}"`);
      return failure(err);
    })
  }).catch(e => {
    console.error(e);
    throw e;
  });
};

const videoTranscode = (inputFilePath, outputFilePath, videoOpts=AOM_AV1_VIDEO_CODEC) => {

  const args = ['-y', '-i', inputFilePath,
    ...VIDEO_FILTERS.split(' '),
    ...videoOpts.split(' '),
    ...HE_AAC_AUDIO_CODEC.split(' '), 
    outputFilePath];
  // progress
  // https://blog.programster.org/ffmpeg-output-progress-to-file
  // job.progress
  // .on('progress', function (job, progress) {
  // A job's progress was updated!

  return transcode(inputFilePath, outputFilePath, args);
};

export {videoTranscode, H264_VIDEO_CODEC, HEVC_VIDEO_CODEC, AOM_AV1_VIDEO_CODEC}
