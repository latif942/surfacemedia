import express from 'express';
import multer from 'multer';
import fetch from 'node-fetch';
import FormData from 'form-data';
import cors from 'cors';
import path from 'path';
import { randomBytes } from 'crypto';
import { pipeline } from 'stream/promises';

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 200 * 1024 * 1024 } });

app.use(cors());

// in-memory map: id -> { catboxUrl, filename }
const files = new Map();

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

    const catboxUrl = (await catboxRes.text()).trim();
    if (!catboxUrl.startsWith('https://')) return res.status(500).send(catboxUrl);

    const id = randomBytes(4).toString('hex');
    const ext = path.extname(req.file.originalname);
    files.set(id, { catboxUrl, filename: req.file.originalname });

    const ourUrl = `${req.protocol}://${req.get('host')}/files/${id}${ext}`;
    res.send(ourUrl);
  } catch (err) {
    res.status(500).send('Proxy error: ' + err.message);
  }
});

app.get('/files/:id', async (req, res) => {
  const id = req.params.id.replace(/\.[^.]+$/, '');
  const entry = files.get(id);
  if (!entry) return res.status(404).send('File not found — server may have restarted');

  try {
    const upstream = await fetch(entry.catboxUrl);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${entry.filename}"`);
    await pipeline(upstream.body, res);
  } catch (err) {
    res.status(502).send('Catbox fetch failed: ' + err.message);
  }
});

app.get('/', (_, res) => res.send('Surface Media — OK'));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Listening on ${PORT}`));