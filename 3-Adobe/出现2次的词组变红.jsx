var doc = app.activeDocument;
var textFrames = doc.textFrames;

// 第一步：统计每个可见图层中字符串出现的次数
var counts = {};
for (var i = 0; i < textFrames.length; i++) {
    var tf = textFrames[i];
    if (!tf.layer.visible) continue;  // 跳过隐藏图层

    var content = tf.contents;
    counts[content] = (counts[content] || 0) + 1;
}

// 准备红色
var red = new RGBColor();
red.red = 255;
red.green = 0;
red.blue = 0;

// 第二步：对出现两次或以上的，在可见图层中标红
var changed = 0;
for (var i = 0; i < textFrames.length; i++) {
    var tf = textFrames[i];
    if (!tf.layer.visible) continue;

    var content = tf.contents;
    if (counts[content] >= 2) {
        tf.textRange.characterAttributes.fillColor = red;
        changed++;
    }
}

alert(changed + " 个文本项被标记为红色。");
