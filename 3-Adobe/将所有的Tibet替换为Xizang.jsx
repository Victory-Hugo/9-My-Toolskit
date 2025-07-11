var doc = app.activeDocument;
var textFrames = doc.textFrames;
var changed = 0;

function replaceText(oldText, newText) {
    for (var i = 0; i < textFrames.length; i++) {
        if (textFrames[i].contents.indexOf(oldText) !== -1) {
            textFrames[i].contents = textFrames[i].contents.replace(new RegExp(oldText, 'g'), newText);
            changed++;
        }
    }
}

replaceText("_Tibet", "_Xizang");

alert(changed + ' text items changed.');
