# Edit plan contract v1

Import an UTF-8 `.json` containing `summary` and `operations`. All optional operation fields can be null; the gateway uses a strict schema with all fields present.

```json
{
  "summary": "أضف نهاية متحركة",
  "operations": [{
    "action": "addText",
    "clipID": null,
    "property": null,
    "number": 2,
    "text": "احفظ الفيديو",
    "time": 20
  }]
}
```

| Action | Meaning |
|---|---|
| `addText` | `time` is timeline start, `number` is duration, `text` is content. |
| `set` | Existing `clipID`, supported `property`, numeric `number` or string `text`. |
| `keyframe` | Existing `clipID`, animated `property`, local `time`, numeric `number`. |
| `remove` | Remove existing `clipID`. |

Numeric properties: `start`, `sourceIn`, `duration`, `speed`, `lane`, `volume`, `x`, `y`, `scale`, `stretch`, `rotation`, `opacity`, `fontSize`, `brightness`, `contrast`, `saturation`.

String properties: `text`, `color` (`#RRGGBB`), `fontName` (registered PostScript name), `motion` (`none`, `fade`, `pop`, `slide`).

Keyframe properties: `x`, `y`, `scale`, `stretch`, `rotation`, `opacity`.

Positions are normalized; y=0 is top. Scale=1 is the default fit. Times are seconds. Layer-local keyframes interpolate with smoothstep. Clip timeline duration multiplied by speed is its required source duration.

Plans apply atomically. Invalid IDs/properties, duration bounds, unsafe asset paths and bad motion values reject the whole plan. JSON import cannot introduce executable scripts or new file references. Source media duration is checked by the renderer.
