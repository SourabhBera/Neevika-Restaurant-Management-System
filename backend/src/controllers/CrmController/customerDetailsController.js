const { CustomerDetails, customerDetailQR, QrOffer } = require('../../models'); 
const ExcelJS = require('exceljs'); 
// Get all customer details
const getAllCustomerDetails = async (req, res) => {
  try {
    const customers = await CustomerDetails.findAll();
    res.status(200).json(customers);
  } catch (error) {
    console.error('Error fetching customer details:', error);
    res.status(500).json({
      message: 'Error fetching customer details',
      error: error.message,
    });
  }
};


const getAllQrCustomerDetails = async (req, res) => {
  try {
    const customers = await customerDetailQR.findAll();
    res.status(200).json(customers);
  } catch (error) {
    console.error('Error fetching customer details:', error);
    res.status(500).json({
      message: 'Error fetching customer details',
      error: error.message,
    });
  }
};


// Download inventory as Excel
const downloadCustomerDetials = async (req, res) => {
  try {
    const customers = await CustomerDetails.findAll();

    const qrCustomers = await customerDetailQR.findAll({
      include: [{
        model: QrOffer,
        as: 'offer', // matches alias in association
        attributes: ['offer_code', 'offer_type', 'offer_value']
      }]
    });

    const workbook = new ExcelJS.Workbook();

    // 📄 Sheet 1: CustomerDetails
    const sheet1 = workbook.addWorksheet('Table Customer Details');
    sheet1.columns = [
      { header: 'ID', key: 'id', width: 10 },
      { header: 'Customer Name', key: 'customer_name', width: 25 },
      { header: 'Customer Phone', key: 'customer_phoneNumber', width: 15 },
    ];

    customers.forEach(item => {
      const data = item.toJSON();
      sheet1.addRow({
        id: data.id ?? 'N/A',
        customer_name: data.customer_name || 'N/A',
        customer_phoneNumber: data.customer_phoneNumber || 'N/A',
      });
    });

    // 📄 Sheet 2: QR Customer Details
    const sheet2 = workbook.addWorksheet('Qr Customer Details');
    sheet2.columns = [
      { header: 'Name', key: 'name', width: 25 },
      { header: 'Phone', key: 'phone', width: 15 },
      { header: 'Email', key: 'email', width: 25 },
      { header: 'Gender', key: 'gender', width: 10 },
      { header: 'Birthday', key: 'birthday', width: 15 },
      { header: 'Anniversary', key: 'anniversary', width: 15 },
      
    ];

    qrCustomers.forEach(item => {
      const data = item.toJSON();
      sheet2.addRow({
        name: data.name || 'N/A',
        phone: data.phone || 'N/A',
        email: data.email || 'N/A',
        gender: data.gender || 'N/A',
        birthday: data.birthday || 'N/A',
        anniversary: data.anniversary || 'N/A',
        
      });
    });

    // 📦 Set headers for Excel download
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    );
    res.setHeader(
      'Content-Disposition',
      'attachment; filename=customer_details.xlsx'
    );

    await workbook.xlsx.write(res);
    res.status(200).end();

  } catch (error) {
    console.error('Error downloading customer details:', error);
    res.status(500).json({
      message: 'Error downloading customer details',
      error: error.message
    });
  }
};

module.exports = { getAllCustomerDetails, downloadCustomerDetials, getAllQrCustomerDetails };
