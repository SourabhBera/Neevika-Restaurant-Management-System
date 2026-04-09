const { Client } = require('pg');
const env = process.env.NODE_ENV ;

const configs = {
  production: {
    host: 'restaurant5k.cd2y8c8624l1.eu-north-1.rds.amazonaws.com',
    port: 5432,
    user: 'postgres',
    password: 'fLQJTBkRPiKFlsKlXW0a',
    database: 'Restaurant5K',
    ssl: { rejectUnauthorized: false }
  },
  development: {
    host: 'localhost',
    port: 5432,
    user: 'postgres',
    password: 'postgres',
    database: 'Restaurant5K_local',
    ssl: false
  }
};

const client = new Client(configs[env]);

client.connect()
  .then(() => console.log(`✅ Connected to ${env} database`))
  .catch(err => console.error('❌ Database connection error:', err));
