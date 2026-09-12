// NODE_PATH points to a Node environment with sharp installed.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const brand = path.join(root, 'assets/brand');
const mark = `<path d="M174 700C202 428 366 224 682 236C480 292 382 402 372 554C496 474 666 488 830 580C634 522 460 574 330 770Z" fill="#FF852D"/><path d="M192 805C382 674 578 666 748 720" fill="none" stroke="#FFB94F" stroke-width="26" stroke-linecap="round"/><circle cx="703" cy="348" r="147" fill="#F5F7FF"/><path d="M703 270L774 322L747 405H659L632 322Z" fill="#101D3D"/><path d="M703 201V270M843 303L774 322M790 467L747 405M616 467L659 405M563 303L632 322" fill="none" stroke="#101D3D" stroke-width="13"/>`;
const svg=(body,w=1024,h=1024)=>`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`;
const bg=`<defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#192D57"/><stop offset="1" stop-color="#081126"/></linearGradient></defs><path fill="url(#bg)" d="M0 0H1024V1024H0Z"/><circle cx="510" cy="510" r="398" fill="none" stroke="#2A3D62" stroke-width="3"/>`;
const icon=svg(bg+mark);
const logo=svg(`<g transform="translate(-30 -50) scale(.6)">${mark}</g><text x="525" y="230" fill="#F5F7FF" font-family="Arial,sans-serif" font-style="italic" font-weight="900" font-size="158">ŞUT VE</text><text x="525" y="410" fill="#FF852D" font-family="Arial,sans-serif" font-style="italic" font-weight="900" font-size="190">GOL</text>`,1260,510);
const defs={play:'M9 5L20 12L9 19Z',pause:'M8 5V19M16 5V19',replay:'M4 10A8 8 0 1 1 5 18M4 4V10H10',goal:'M3 20V5H21V20M3 10H21M3 15H21M8 5V20M16 5V20',sound:'M3 9H7L12 5V19L7 15H3ZM16 8Q21 12 16 16',mute:'M3 9H7L12 5V19L7 15H3ZM17 9L22 15M22 9L17 15',heart:'M12 21L3 12C-2 4 8 0 12 7C16 0 26 4 21 12Z',trophy:'M7 3H17V10Q17 15 12 15Q7 15 7 10ZM7 5H3V8Q3 11 7 11M17 5H21V8Q21 11 17 11M12 15V21M8 21H16',curve:'M4 21C4 5 19 19 19 3M14 6L19 3L22 8',target:'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2M12 7A5 5 0 1 0 12 17A5 5 0 1 0 12 7',shield:'M12 2L21 6V12Q21 19 12 22Q3 19 3 12V6ZM8 12L11 15L17 9',back:'M15 4L7 12L15 20',close:'M5 5L19 19M19 5L5 19',help:'M9 8Q9 3 14 5Q19 8 12 12V14M12 18V19',settings:'M12 8A4 4 0 1 0 12 16A4 4 0 1 0 12 8M12 2V5M12 19V22M2 12H5M19 12H22M5 5L7 7M17 17L19 19M5 19L7 17M17 7L19 5',lightning:'M14 2L4 14H11L10 22L20 10H13Z'};
(async()=>{
fs.writeFileSync(path.join(brand,'mark.svg'),svg(mark));
fs.writeFileSync(path.join(brand,'app-icon.svg'),icon);
fs.writeFileSync(path.join(brand,'logo.svg'),logo);
fs.writeFileSync(path.join(brand,'mark-white.svg'),svg(mark.replaceAll('#FF852D','#FFFFFF').replaceAll('#FFB94F','#FFFFFF').replaceAll('#F5F7FF','#FFFFFF')));
await sharp(Buffer.from(icon)).png().toFile(path.join(brand,'app-icon.png'));
await sharp(Buffer.from(logo)).png().toFile(path.join(brand,'logo.png'));
for(const [name,d] of Object.entries(defs))fs.writeFileSync(path.join(brand,'icons',`${name}.svg`),svg(`<path d="${d}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`,24,24));
const ios=path.join(root,'ios/Runner/Assets.xcassets/AppIcon.appiconset');
for(const item of JSON.parse(fs.readFileSync(path.join(ios,'Contents.json'))).images){if(!item.filename)continue;const n=Math.round(parseFloat(item.size)*parseFloat(item.scale));await sharp(Buffer.from(icon)).resize(n,n).removeAlpha().png().toFile(path.join(ios,item.filename));}
for(const [folder,n] of Object.entries({'mipmap-mdpi':48,'mipmap-hdpi':72,'mipmap-xhdpi':96,'mipmap-xxhdpi':144,'mipmap-xxxhdpi':192}))await sharp(Buffer.from(icon)).resize(n,n).png().toFile(path.join(root,'android/app/src/main/res',folder,'ic_launcher.png'));
for(const f of ['app-icon.png','logo.svg','mark.svg'])fs.copyFileSync(path.join(brand,f),path.join(root,'docs/assets',f));
console.log('Logo, marka amblemi, 16 SVG ikon ve iOS/Android ikonları üretildi.');
})();
