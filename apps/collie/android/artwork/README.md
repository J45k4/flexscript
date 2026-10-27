# Collie icon

The launcher and in-app mark use `../res/drawable-nodpi/collie_border_collie.png`,
generated with the built-in image generation tool. The transparent PNG depicts a black-and-white
border collie wearing dark sunglasses and typing on a keyboard with its front
paws, while keeping its white blaze and folded ear.

`collie_mark.xml` adds 27% padding on every edge for adaptive icon masks.
The background keeps the app's dark green. Android 13+ also gets a native vector
monochrome mark with sunglasses and a keyboard for themed launchers.
The in-app avatar uses the same artwork with less padding because it is not
subject to launcher masks. Android's drawable renderer scales the
original artwork; no runtime network access or image-generation dependency is used.

Original generation prompt:

Use case: logo-brand. Asset type: Android app launcher icon foreground for Collie, a thoughtful AI companion. Create one beautiful, polished, memorable icon illustration inspired by a real black-and-white border collie dog. Subject: a close frontal head portrait with a little fluffy neck ruff, classic broad white blaze running between expressive warm brown eyes to a white muzzle, black cheeks, glossy black nose, one upright ear and one gently folded ear, alert friendly intelligent expression. Style: premium contemporary mascot illustration with softly sculpted shapes, subtle realistic fur edge detail, restrained dimensional shading, strong clean silhouette and excellent legibility at 48px; clearly a border collie, anatomically canine, not a fox, wolf or cat. Composition: square 1024x1024, centered complete head including both ears, with generous transparent margin; all visible artwork must fit inside a centered circle of diameter 620px, so it is safe in Android adaptive icon masks. Head fills that safe circle with balanced visual weight. Natural black and creamy white fur, warm brown eyes. Lighting: gentle warm studio light with crisp expressive facial features. Background: genuinely transparent, no shadow extending into the transparent margin. No text, letters, typography, badge, border, container, rounded-square tile, accessories or watermark. Deliver just the isolated dog head artwork on transparency.

Edit prompt (built-in image generation, using the original PNG as reference):

Use case: precise-object-edit / app icon. Edit the attached Collie artwork into a border collie using a computer keyboard while wearing sunglasses. Preserve this dog's recognizable black-and-white markings, broad white forehead blaze, black cheeks, fluffy white chest, black nose, one upright ear and one folded ear, and polished softly realistic illustration style. Add stylish dark charcoal sunglasses sitting naturally across the dog's eyes, with subtle cool reflections, and a compact dark computer keyboard across the lower foreground. Show both canine front paws resting on the keys as if confidently typing; real furry dog paws, no human hands. Frame a compact frontal bust: the large expressive dog head dominates the upper two thirds, fluffy chest and paws lead down to a clearly recognizable keyboard with three simple rows of large contrasting keys. Cool, friendly, clever coder-dog expression. The keyboard must remain readable at small app-icon sizes. Keep a balanced, centered, roughly circular silhouette with both ears, paws, and the complete keyboard visible. Transparent square canvas, generous clear space at the outer corners for Android icon masks. No monitor, desk, cables, extra characters, lettering, labels, logos, watermark, border, badge, rounded-square tile or solid background. Clean isolated artwork only, with genuine transparent alpha. Make this feel like a premium memorable Android app icon.
