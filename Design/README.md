# Иконка приложения

Исходники в SVG (1024×1024), готовые PNG лежат в
`TripAtlas/Resources/Assets.xcassets/AppIcon.appiconset/`.

| Файл | Где используется |
|------|------------------|
| `AppIcon.svg` | обычная иконка |
| `AppIcon-Dark.svg` | тёмный режим главного экрана (iOS 18+) |
| `AppIcon-Tinted.svg` | тонированный режим — система перекрашивает градации серого |

Чтобы пересобрать PNG после правки SVG:

```bash
brew install librsvg
for f in AppIcon AppIcon-Dark AppIcon-Tinted; do
  rsvg-convert -w 1024 -h 1024 -b black "Design/$f.svg" \
    -o "TripAtlas/Resources/Assets.xcassets/AppIcon.appiconset/$f.png"
done
```

PNG должны быть без прозрачности и без скруглений — углы iOS обрежет сама.
