# Эталон IMPORT .zip (S11c): архив со сжатием deflate, как делают «Файлы» iPad и другие программы
# (папки, вложенная папка, пустая папка, пресет, служебные файлы macOS, большой сжимаемый файл).
# Выход: ios/tools/zip/deflated.zip. Запуск: python3 ios/tools/zip/golden.py
import json, os, zipfile

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, 'deflated.zip')
preset = json.dumps({'jambo': 'preset', 'preset': {'name': 'Bell', 'sound': 'mi:2', 'params': {'harm': 30}, 'fmt': 2}})
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('Kit/', b'')
    z.writestr('Kit/Empty/', b'')
    z.writestr('Kit/Sub/text.wav', b'RIFF' + bytes(range(256)) * 40)
    z.writestr('Kit/Bell.jambopreset', preset)
    z.writestr('Kit/.DS_Store', b'junk')
    z.writestr('__MACOSX/Kit/._x', b'junk')
    z.writestr('big.bin', (b'abcabcabd' * 5000) + bytes(i * 7 % 251 for i in range(20000)))
print(out, os.path.getsize(out))
