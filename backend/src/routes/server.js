const express = require('express');
const logger = require('../configs/logger');
const router = express.Router();

router.get('/health', (req, res) => {
  res.status(200).json({ message: 'API is running!' });
});


router.get('/test', (req, res)=>{
  logger.info("im in testing");
  res.status(200).json({message:'Testing this route'})
});

module.exports = router;