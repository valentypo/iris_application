from flask import Flask, jsonify, request
from flask_cors import CORS
from ultralytics import YOLO
import base64
from PIL import Image
import io
import numpy as np
import logging

app = Flask(__name__)
CORS(app)

# Configure logging
logging.basicConfig(level=logging.INFO)

# Increase max content length to 16MB for larger images
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024

# Load model once when server starts
print("Loading YOLO model...")
model = YOLO("yolo11n.pt")
print("Model loaded successfully!")

@app.route('/detect', methods=['POST'])
def detect():
    try:
        # Log request received
        app.logger.info("Detection request received")
        
        # Get JSON data
        if not request.is_json:
            return jsonify({
                'success': False,
                'error': 'Content-Type must be application/json'
            }), 400
            
        data = request.get_json()
        
        if 'image' not in data:
            return jsonify({
                'success': False,
                'error': 'No image data provided'
            }), 400
            
        image_base64 = data['image']
        
        # Decode base64 image
        try:
            image_data = base64.b64decode(image_base64)
            image = Image.open(io.BytesIO(image_data))
            
            # Convert RGBA to RGB if necessary
            if image.mode == 'RGBA':
                rgb_image = Image.new('RGB', image.size, (255, 255, 255))
                rgb_image.paste(image, mask=image.split()[3])
                image = rgb_image
            
        except Exception as e:
            app.logger.error(f"Image decode error: {str(e)}")
            return jsonify({
                'success': False,
                'error': f'Invalid image data: {str(e)}'
            }), 400
        
        # Log image info
        app.logger.info(f"Image size: {image.size}, mode: {image.mode}")
        
        # Run YOLO detection
        results = model(image)
        
        # Process results
        detections = []
        for r in results:
            boxes = r.boxes
            if boxes is not None:
                for box in boxes:
                    detection = {
                        'class': r.names[int(box.cls)],
                        'confidence': float(box.conf),
                        'bbox': box.xyxy[0].tolist()  # [x1, y1, x2, y2]
                    }
                    detections.append(detection)
        
        app.logger.info(f"Found {len(detections)} objects")
        
        return jsonify({
            'success': True,
            'detections': detections,
            'count': len(detections)
        })
    
    except Exception as e:
        app.logger.error(f"Detection error: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'healthy',
        'model': 'yolo11n',
        'version': '1.0'
    })

@app.route('/', methods=['GET'])
def home():
    return jsonify({
        'message': 'YOLO Object Detection API',
        'endpoints': {
            '/health': 'GET - Check API health',
            '/detect': 'POST - Detect objects in image'
        }
    })

if __name__ == '__main__':
    print("Starting Flask server...")
    print("Server will be available at:")
    print("  - http://localhost:5000")
    print("  - http://172.20.10.5:5000")
    print("\nPress CTRL+C to stop the server")
    
    app.run(host='0.0.0.0', port=5000, debug=True)