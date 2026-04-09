const express = require("express");
const router = express.Router();
const incidentController = require("../../controllers/IncidentController/incidentController");
const createUploadMiddleware = require("../../middlewares/multipleImageUploadMiddleware");
const uploadIncidentImages = createUploadMiddleware("incidents", "images", 10);

// Create new incident
router.post("/", uploadIncidentImages, incidentController.createIncident);

// Get all incidents
router.get("/", incidentController.getAllIncidents);

// Get incidents by userId
router.get("/user/:userId", async (req, res) => {
  try {
    const { userId } = req.params;
    const { IncidentReport } = require("../models");

    const incidents = await IncidentReport.findAll({
      where: { userId },
      order: [["incidentDate", "DESC"]],
    });

    if (!incidents || incidents.length === 0) {
      return res.status(404).json({ message: "No incidents found for this user" });
    }

    res.json(incidents);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: "Error fetching incidents for user" });
  }
});

// Get single incident by ID
router.get("/:id", incidentController.getIncident);

// Update incident (with optional new images)
router.put("/:id", uploadIncidentImages, incidentController.updateIncident);

// Delete incident
router.delete("/:id", incidentController.deleteIncident);

module.exports = router;