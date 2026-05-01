import express from 'express';
import multer from 'multer';
import fetch from 'node-fetch';
import FormData from 'form-data';
import cors from 'cors';

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 200 * 1024 * 1024 } });

app.use(cors());

app.post('/upload', upload.single('fileToUpload'), async (req, res) => {
  try {
    const form = new FormData();
    form.append('reqtype', 'fileupload');
    if (req.body.userhash) form.append('userhash', req.body.userhash);
    form.append('fileToUpload', req.file.buffer, {
      filename: req.file.originalname,
      contentType: req.file.mimetype,
    });

    const catboxRes = await fetch('https://catbox.moe/user/api.php', {
      method: 'POST',
      body: form,
      headers: form.getHeaders(),
    });

    const text = await catboxRes.text();
    res.send(text);
  } catch (err) {
    res.status(500).send('Proxy error: ' + err.message);
  }
});

app.get('/', (_, res) => res.send('Surface Media proxy — OK'));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Listening on ${PORT}`));