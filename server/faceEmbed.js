// Вычисление эмбеддинга лица НА СЕРВЕРЕ из загруженного фото.
// Это защита «максимум»: даже если мобильное приложение взломают и пришлют
// поддельный «совпадающий» вектор — он не используется. Сервер сам детектит
// лицо на снимке и считает 128-мерный дескриптор (face-api / TensorFlow).

import { createRequire } from 'node:module';
import { join } from 'node:path';

const require = createRequire(import.meta.url);

let faceapi = null;
let tf = null;
let ready = false;
let loadingError = null;

/// Ленивая загрузка моделей (модели поставляются внутри npm-пакета face-api —
/// вендорить в репозиторий ничего не нужно).
export async function initFaceEmbed() {
  if (ready) return true;
  if (loadingError) return false;
  try {
    faceapi = require('@vladmandic/face-api/dist/face-api.node.js');
    tf = faceapi.tf;
    const pkg = require.resolve('@vladmandic/face-api/package.json');
    const modelPath = join(pkg, '..', 'model');
    await tf.ready();
    await faceapi.nets.ssdMobilenetv1.loadFromDisk(modelPath);
    await faceapi.nets.faceLandmark68Net.loadFromDisk(modelPath);
    await faceapi.nets.faceRecognitionNet.loadFromDisk(modelPath);
    ready = true;
    console.log('face-api: модели распознавания загружены (backend=%s)', tf.getBackend());
    return true;
  } catch (e) {
    loadingError = e;
    console.warn('face-api недоступен, серверный эмбеддинг выключен:', e.message);
    return false;
  }
}

export function isReady() {
  return ready;
}

/// Принимает data-URL или base64 картинки, возвращает { descriptor:number[128] }
/// или null, если лицо не найдено. Бросает, если модуль не готов.
export async function embedFromDataUrl(dataUrl) {
  if (!ready) throw new Error('face-api не инициализирован');
  const m = typeof dataUrl === 'string' ? dataUrl.match(/^data:image\/\w+;base64,(.+)$/s) : null;
  const b64 = m ? m[1] : dataUrl;
  const buf = Buffer.from(b64, 'base64');
  const tensor = tf.node.decodeImage(buf, 3);
  try {
    const res = await faceapi
      .detectSingleFace(tensor, new faceapi.SsdMobilenetv1Options({ minConfidence: 0.4 }))
      .withFaceLandmarks()
      .withFaceDescriptor();
    if (!res) return null;
    return { descriptor: Array.from(res.descriptor) };
  } finally {
    tensor.dispose();
  }
}
