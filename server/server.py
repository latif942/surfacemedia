from flask import Flask, request, Response, jsonify
import yt_dlp
import os
import requests

app = Flask(__name__)

def get_audio_url(query):
    opts = {
        'format': 'bestaudio/best',
        'quiet': True,
        'noplaylist': True,
        'nocheckcertificate': True,
        'extractor_args': {
            'youtube': {
                'player_client': ['ios'],
            }
        }
    }
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f"ytsearch1:{query}", download=False)
        entries = info.get('entries') or [info]
        if not entries:
            raise Exception("No results found")
        return entries[0]['url']

@app.route('/stream')
def stream():
    q = request.args.get('q', '')
    if not q:
        return jsonify({'error': 'no query'}), 400
    try:
        url = get_audio_url(q)
        def generate():
            headers = {'User-Agent': 'com.google.ios.youtube/19.09.3 CFNetwork/1220.1 Darwin/20.3.0'}
            with requests.get(url, headers=headers, stream=True) as r:
                for chunk in r.iter_content(chunk_size=8192):
                    if chunk:
                        yield chunk
        return Response(generate(), mimetype='audio/mp4')
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/health')
def health():
    return 'ok'

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)