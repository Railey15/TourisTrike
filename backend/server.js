const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const OpenAI = require("openai");

dotenv.config();

const app = express();

app.use(cors());
app.use(express.json());

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

app.post("/chat", async (req, res) => {
  try {
    const userMessage = req.body.message;

    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "developer",
          content: `
You are the tourism AI assistant for TourisTrike.

You help tourists with:
- municipalities
- tourist destinations
- transportation
- travel routes
- tourism packages
- café hopping
- travel planning
- local attractions

Only answer tourism-related questions.
If unrelated questions are asked, politely refuse.
          `,
        },
        {
          role: "user",
          content: userMessage,
        },
      ],
    });

    res.json({
      reply: completion.choices[0].message.content,
    });
  } catch (error) {
    console.log(error);

    res.status(500).json({
      error: "Something went wrong",
    });
  }
});

app.listen(process.env.PORT, () => {
  console.log(
    `TourisTrike chatbot backend running on http://localhost:${process.env.PORT}`
  );
});