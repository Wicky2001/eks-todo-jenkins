require("dotenv").config();

if (process.env.NODE_ENV == "production") {
  require("./tracing");
}

const app = require("./app");
const connectToDatabase = require("./config/db");

const PORT = process.env.PORT || 4000;

async function startServer() {
  try {
    await connectToDatabase();

    app.listen(PORT, () => {
      console.log(`Backend API listening on port ${PORT}`);
    });
  } catch (error) {
    console.error("Unable to start backend server:", error.message);
    process.exit(1);
  }
}

void startServer();
