const fs = require('fs');
const path = require('path');
const canvas = require('canvas');
const faceapi = require('@vladmandic/face-api');
const { User } = require('../../models'); // Adjust path as per your project

// Required for face-api with Node
const { Canvas, Image, ImageData } = canvas;
faceapi.env.monkeyPatch({ Canvas, Image, ImageData });

const MODEL_PATH = path.join(__dirname, '..', 'models', 'face-api'); // e.g., models/face-api

let modelsLoaded = false;
async function loadModels() {
  if (modelsLoaded) return;
  await faceapi.nets.ssdMobilenetv1.loadFromDisk(MODEL_PATH);
  await faceapi.nets.faceRecognitionNet.loadFromDisk(MODEL_PATH);
  await faceapi.nets.faceLandmark68Net.loadFromDisk(MODEL_PATH);
  modelsLoaded = true;
}

const enrollFace = async (req, res) => {
  const { userId } = req.body;

  if (!req.file || !userId) {
    return res.status(400).json({ error: 'Image and userId are required' });
  }

  try {
    await loadModels();

    const imagePath = req.file.path;
    const img = await canvas.loadImage(imagePath);

    const detection = await faceapi
      .detectSingleFace(img)
      .withFaceLandmarks()
      .withFaceDescriptor();

    if (!detection) {
      fs.unlinkSync(imagePath);
      return res.status(400).json({ error: 'No face detected in image' });
    }

    const descriptor = Array.from(detection.descriptor); // convert Float32Array to normal array

    // Save descriptor to DB
    const user = await User.findByPk(userId);
    if (!user) {
      fs.unlinkSync(imagePath);
      return res.status(404).json({ error: 'User not found' });
    }

    await user.update({ face_descriptor: descriptor });

    fs.unlinkSync(imagePath); // delete uploaded image after processing

    res.json({ success: true, message: 'Face enrolled successfully' });
  } catch (error) {
    console.error('Error enrolling face:', error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
};

module.exports = { enrollFace };
