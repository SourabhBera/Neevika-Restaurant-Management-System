// controllers/incidentReportController.js
const path = require("path");
const { IncidentReport } = require("../../models");

module.exports = {
  // Create new incident
  async createIncident(req, res) {
    try {
      const { title, description, incidentDate, userId } = req.body;

      // If images were uploaded, map to relative paths
      let uploadedImages = [];
      if (req.files && req.files.length > 0) {
        uploadedImages = req.files.map(file =>
          path.relative(path.resolve(__dirname, "../../"), file.path) // store relative path
        );
      }

      const incident = await IncidentReport.create({
        title,
        description,
        incidentDate,
        images: uploadedImages,
        userId,
      });

      res.status(201).json(incident);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: "Error creating incident report" });
    }
  },

  // Get all incidents
  async getAllIncidents(req, res) {
    try {
      const incidents = await IncidentReport.findAll({
        order: [["incidentDate", "DESC"]],
      });
      res.json(incidents);
    } catch (error) {
      res.status(500).json({ message: "Error fetching incidents" });
    }
  },

  // Get single incident
  async getIncident(req, res) {
    try {
      const { id } = req.params;
      const incident = await IncidentReport.findByPk(id);
      if (!incident) return res.status(404).json({ message: "Not found" });
      res.json(incident);
    } catch (error) {
      res.status(500).json({ message: "Error fetching incident" });
    }
  },

  // Update incident
  async updateIncident(req, res) {
    try {
      const { id } = req.params;
      const { title, description, incidentDate, userId } = req.body;

      const incident = await IncidentReport.findByPk(id);
      if (!incident) return res.status(404).json({ message: "Not found" });

      // Handle new images if uploaded
      let uploadedImages = incident.images || [];
      if (req.files && req.files.length > 0) {
        const newImages = req.files.map(file =>
          path.relative(path.resolve(__dirname, "../../"), file.path)
        );
        uploadedImages = [...uploadedImages, ...newImages];
      }

      await incident.update({
        title,
        description,
        incidentDate,
        userId,
        images: uploadedImages,
      });

      res.json(incident);
    } catch (error) {
      res.status(500).json({ message: "Error updating incident" });
    }
  },

  // Delete incident
  async deleteIncident(req, res) {
    try {
      const { id } = req.params;
      const incident = await IncidentReport.findByPk(id);
      if (!incident) return res.status(404).json({ message: "Not found" });

      await incident.destroy();
      res.json({ message: "Incident deleted successfully" });
    } catch (error) {
      res.status(500).json({ message: "Error deleting incident" });
    }
  },
};
