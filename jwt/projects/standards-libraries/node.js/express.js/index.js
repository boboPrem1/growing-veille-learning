import express from "express";
import { config } from "@dotenvx/dotenvx";
import jsonWebTokenRoutes from "./src/endpoints/json-web-tokens/routes.js";
import joseRoutes from "./src/endpoints/jose/routes.js";
config();

const app = express();
const port = 3000;

app.use(express.json());

app.use("/json-web-token", jsonWebTokenRoutes);
app.use("/jose", joseRoutes);

app.get("/", (req, res) => {
  res.status(200).json({
    message: "Welcome to the Express API with JWT authentication!",
  });
});

app.listen(port, () => {
  console.log("Express app listening on port 3000.");
});
