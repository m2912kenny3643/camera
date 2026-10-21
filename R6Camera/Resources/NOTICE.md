# Object detection model

The build downloads Apple's Core ML YOLOv3 Tiny Int8 LUT model from:
https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyInt8LUT.mlmodel

Catalogue: https://developer.apple.com/machine-learning/models/
Upstream labels and code: https://github.com/pjreddie/darknet
Upstream license: https://github.com/pjreddie/darknet/blob/master/LICENSE

The detector contains COCO categories. Only person, dog, cat, bird, horse,
car, motorcycle, airplane, and train are exposed by this application.
Human eye landmarks and cat/dog pose landmarks are provided by Apple Vision.
Bird/horse eye localization is not included. No Canon software, models,
logos, or manual images are distributed with this app.

This app is an independent project and is not affiliated with Canon or Apple.
