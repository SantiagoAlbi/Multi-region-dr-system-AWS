from flask import Flask, jsonify
import os


app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        'status': 'healthy',
        'message': 'DR System Running',
        'region': os.getenv('AWS_REGION', 'us-east-1')
    })

@app.route('/health')
def health():
    return jsonify({'status': 'ok'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
