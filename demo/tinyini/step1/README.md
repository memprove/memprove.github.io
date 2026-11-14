# tinyini

A small INI parser. It exists so that memprove.dev can show real memprove
output: `demo/record.sh` in the site repository builds this repository commit
by commit and records every command it runs.

```python
from tinyini import parse

parse("[core]\nname = demo\n")   # {"core": {"name": "demo"}}
```
