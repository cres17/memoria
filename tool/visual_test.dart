// ignore_for_file: avoid_print
/// Visual algorithm test — no real photos needed.
/// Generates synthetic style images and applies both OLD/NEW algorithms,
/// saving side-by-side comparison PNGs.
///
/// Run:  dart run tool/visual_test.dart [out_dir]
/// Default out_dir: tool/test_output

library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// ──────────────────────────────────────────────────────────────────────────────
// Color utils (self-contained copy)
// ──────────────────────────────────────────────────────────────────────────────

const _xn = 0.95047, _yn = 1.00000, _zn = 1.08883;
double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _delin(double c) => c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1.0 / 2.4) - 0.055;
double _f(double t) { const d = 6.0/29.0; return t > d*d*d ? math.pow(t,1.0/3.0).toDouble() : t/(3*d*d)+4.0/29.0; }
double _fi(double t) { const d = 6.0/29.0; return t > d ? t*t*t : 3*d*d*(t-4.0/29.0); }

class _Lab { final double l, a, b; const _Lab(this.l, this.a, this.b); }
class _Rgb { final double r, g, b; const _Rgb(this.r, this.g, this.b); }

_Lab _toL(_Rgb c) {
  final rl=_lin(c.r), gl=_lin(c.g), bl=_lin(c.b);
  final x=0.4124564*rl+0.3575761*gl+0.1804375*bl;
  final y=0.2126729*rl+0.7151522*gl+0.0721750*bl;
  final z=0.0193339*rl+0.1191920*gl+0.9503041*bl;
  return _Lab(116*_f(y/_yn)-16, 500*(_f(x/_xn)-_f(y/_yn)), 200*(_f(y/_yn)-_f(z/_zn)));
}
_Rgb _toR(_Lab c) {
  final fy=(c.l+16)/116, fx=c.a/500+fy, fz=fy-c.b/200;
  final x=_fi(fx)*_xn, y=_fi(fy)*_yn, z=_fi(fz)*_zn;
  final rl= 3.2404542*x-1.5371385*y-0.4985314*z;
  final gl=-0.9692660*x+1.8760108*y+0.0415560*z;
  final bl= 0.0556434*x-0.2040259*y+1.0572252*z;
  return _Rgb(_delin(rl.clamp(0,1)), _delin(gl.clamp(0,1)), _delin(bl.clamp(0,1)));
}

// ──────────────────────────────────────────────────────────────────────────────
// Neutral channel CDF  N(μ=115, σ=55)
// ──────────────────────────────────────────────────────────────────────────────

final List<double> _nCdf = () {
  const mu=115.0, sig=55.0;
  final h=List<double>.filled(256,0.0);
  for(int i=0;i<256;i++){ final z=(i-mu)/sig; h[i]=math.exp(-0.5*z*z); }
  final s=h.fold(0.0,(a,b)=>a+b);
  double c=0; final cdf=List<double>.filled(256,0.0);
  for(int i=0;i<256;i++){ c+=h[i]/s; cdf[i]=c; }
  return cdf;
}();

final List<double> _nLCdf = () {
  const mu=50.0, sig=18.0;
  final h=List<double>.filled(256,0.0);
  for(int i=0;i<256;i++){ final l=i*100.0/255.0; final z=(l-mu)/sig; h[i]=math.exp(-0.5*z*z); }
  final s=h.fold(0.0,(a,b)=>a+b);
  double c=0; final cdf=List<double>.filled(256,0.0);
  for(int i=0;i<256;i++){ c+=h[i]/s; cdf[i]=c; }
  return cdf;
}();

// ──────────────────────────────────────────────────────────────────────────────
// Style analysis
// ──────────────────────────────────────────────────────────────────────────────

class _ZoneCast { final double a,b; const _ZoneCast(this.a,this.b); }

class _StyleProfile {
  final List<int> rC,gC,bC;
  final _ZoneCast s,m,h;
  const _StyleProfile(this.rC,this.gC,this.bC,this.s,this.m,this.h);
}

List<int> _curve(List<int> hist) {
  final tot=hist.fold(0,(a,b)=>a+b); double c=0;
  final sc=List<double>.filled(256,0.0);
  for(int i=0;i<256;i++){ c+=hist[i]/tot; sc[i]=c; }
  final curve=List<int>.filled(256,0);
  for(int i=0;i<256;i++){
    final t=_nCdf[i]; int j=0;
    while(j<255&&sc[j]<t) j++;
    curve[i]=j;
  }
  for(int i=1;i<256;i++) if(curve[i]<curve[i-1]) curve[i]=curve[i-1];
  return curve;
}

_StyleProfile _analyze(img.Image im) {
  final rH=List<int>.filled(256,0), gH=List<int>.filled(256,0), bH=List<int>.filled(256,0);
  var sSumA=0.0,sSumB=0.0, mSumA=0.0,mSumB=0.0, hSumA=0.0,hSumB=0.0;
  int sC=0,mC=0,hC=0;
  for(int y=0;y<im.height;y++) for(int x=0;x<im.width;x++){
    final px=im.getPixel(x,y);
    final r=px.rNormalized.toDouble(), g=px.gNormalized.toDouble(), b=px.bNormalized.toDouble();
    rH[(r*255).round().clamp(0,255)]++;
    gH[(g*255).round().clamp(0,255)]++;
    bH[(b*255).round().clamp(0,255)]++;
    final lab=_toL(_Rgb(r,g,b));
    if(lab.l<35){ sSumA+=lab.a; sSumB+=lab.b; sC++; }
    else if(lab.l<65){ mSumA+=lab.a; mSumB+=lab.b; mC++; }
    else{ hSumA+=lab.a; hSumB+=lab.b; hC++; }
  }
  return _StyleProfile(
    _curve(rH), _curve(gH), _curve(bH),
    sC>10 ? _ZoneCast(sSumA/sC,sSumB/sC) : const _ZoneCast(0,0),
    mC>10 ? _ZoneCast(mSumA/mC,mSumB/mC) : const _ZoneCast(0,0),
    hC>10 ? _ZoneCast(hSumA/hC,hSumB/hC) : const _ZoneCast(0,0),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Float16 helpers
// ──────────────────────────────────────────────────────────────────────────────

int _h16(double v){ final f=Float32List(1)..[0]=v; final bits=f.buffer.asUint32List()[0]; final sign=(bits>>31)&1; var e=((bits>>23)&0xFF)-127+15; var m=(bits>>13)&0x3FF; if(e<=0){e=0;m=0;} if(e>=31){e=31;m=0;} return (sign<<15)|(e<<10)|m; }
double _f16(int h){ final e=(h>>10)&0x1F, m=h&0x3FF; if(e==0)return 0; if(e==31)return double.infinity; return ((h>>15)==0?1:-1)*(1+m/1024.0)*math.pow(2,e-15); }

// ──────────────────────────────────────────────────────────────────────────────
// NEW algorithm — per-channel curves + zone Lab tint
// ──────────────────────────────────────────────────────────────────────────────

Uint8List _lutNew(_StyleProfile p) {
  const dim=33, tot=dim*dim*dim;
  final lut=Uint16List(tot*3); int idx=0;
  for(int r=0;r<dim;r++) for(int g=0;g<dim;g++) for(int b=0;b<dim;b++){
    final r8=(r/32.0*255).round().clamp(0,255);
    final g8=(g/32.0*255).round().clamp(0,255);
    final b8=(b/32.0*255).round().clamp(0,255);
    final r1=p.rC[r8]/255.0, g1=p.gC[g8]/255.0, b1=p.bC[b8]/255.0;
    final lab=_toL(_Rgb(r1,g1,b1));
    double gw(double l,double c){ final d=l-c; return math.exp(-0.5*d*d/(25.0*25.0)); }
    final ws=gw(lab.l,17.5), wm=gw(lab.l,50.0), wh=gw(lab.l,82.5);
    final wT=ws+wm+wh+1e-10;
    const ts=0.15;
    final aO=(lab.a+ts*(ws*p.s.a+wm*p.m.a+wh*p.h.a)/wT).clamp(-110.0,110.0);
    final bO=(lab.b+ts*(ws*p.s.b+wm*p.m.b+wh*p.h.b)/wT).clamp(-110.0,110.0);
    final o=_toR(_Lab(lab.l,aO,bO));
    lut[idx++]=_h16(o.r.clamp(0,1)); lut[idx++]=_h16(o.g.clamp(0,1)); lut[idx++]=_h16(o.b.clamp(0,1));
  }
  return lut.buffer.asUint8List();
}

// ──────────────────────────────────────────────────────────────────────────────
// OLD algorithm — Lab zone push with satBoost
// ──────────────────────────────────────────────────────────────────────────────

Uint8List _lutOld(img.Image style) {
  final rH=List<int>.filled(256,0);
  var sSumA=0.0,sSumB=0.0,sSumL=0.0, mSumA=0.0,mSumB=0.0,mSumL=0.0, hSumA=0.0,hSumB=0.0,hSumL=0.0;
  int sC=0,mC=0,hC=0;
  final lv=<double>[], av=<double>[], bv=<double>[];
  final lH=List<int>.filled(256,0);
  for(int y=0;y<style.height;y++) for(int x=0;x<style.width;x++){
    final px=style.getPixel(x,y);
    final r=px.rNormalized.toDouble(), g=px.gNormalized.toDouble(), b=px.bNormalized.toDouble();
    rH[(r*255).round().clamp(0,255)]++;
    final lab=_toL(_Rgb(r,g,b));
    lv.add(lab.l); av.add(lab.a); bv.add(lab.b);
    lH[(lab.l*255/100).round().clamp(0,255)]++;
    if(lab.l<35){ sSumA+=lab.a; sSumB+=lab.b; sSumL+=lab.l; sC++; }
    else if(lab.l<65){ mSumA+=lab.a; mSumB+=lab.b; mSumL+=lab.l; mC++; }
    else{ hSumA+=lab.a; hSumB+=lab.b; hSumL+=lab.l; hC++; }
  }
  final n=lv.length.toDouble();
  final muL=lv.fold(0.0,(s,v)=>s+v)/n, muA=av.fold(0.0,(s,v)=>s+v)/n, muB=bv.fold(0.0,(s,v)=>s+v)/n;
  final sigL=math.sqrt(lv.fold(0.0,(s,v){final d=v-muL;return s+d*d;})/n).clamp(0.001,99.0);
  final sigA=math.sqrt(av.fold(0.0,(s,v){final d=v-muA;return s+d*d;})/n).clamp(0.001,99.0);
  final sigB=math.sqrt(bv.fold(0.0,(s,v){final d=v-muB;return s+d*d;})/n).clamp(0.001,99.0);
  final tot=lH.fold(0,(a,b)=>a+b); double c=0;
  final sCdf=List<double>.filled(256,0.0);
  for(int i=0;i<256;i++){ c+=lH[i]/tot; sCdf[i]=c; }
  final tc=List<double>.filled(256,0.0);
  for(int i=0;i<256;i++){ final t=_nLCdf[i]; int j=0; while(j<255&&sCdf[j]<t) j++; tc[i]=j.toDouble(); }
  for(int i=1;i<tc.length;i++) if(tc[i]<tc[i-1]) tc[i]=tc[i-1];
  final ratioL=(sigL/18.0).clamp(0.7,1.4);
  final satBoost=((sigA+sigB)/16.0).clamp(0.85,1.8);
  final sLab=sC>0?_Lab(sSumL/sC,sSumA/sC,sSumB/sC):const _Lab(17.5,0,0);
  final mLab=mC>0?_Lab(mSumL/mC,mSumA/mC,mSumB/mC):_Lab(50,muA,muB);
  final hLab=hC>0?_Lab(hSumL/hC,hSumA/hC,hSumB/hC):const _Lab(82.5,0,0);
  const dim=33; final lut=Uint16List(dim*dim*dim*3); int idx=0;
  for(int r=0;r<dim;r++) for(int g=0;g<dim;g++) for(int b=0;b<dim;b++){
    final lab=_toL(_Rgb(r/32.0,g/32.0,b/32.0));
    final lBin=(lab.l*255/100).round().clamp(0,255);
    final l1=tc[lBin]*100/255;
    final lOut=(l1-50)*ratioL+muL;
    double gw(double l,double center){ final d=l-center; return math.exp(-0.5*d*d/484); }
    final ws=gw(lOut,sLab.l), wm=gw(lOut,mLab.l), wh=gw(lOut,hLab.l);
    final wT=ws+wm+wh+1e-10;
    final zA=(ws*sLab.a+wm*mLab.a+wh*hLab.a)/wT;
    final zB=(ws*sLab.b+wm*mLab.b+wh*hLab.b)/wT;
    final aO=(lab.a*satBoost+0.45*zA).clamp(-110.0,110.0);
    final bO=(lab.b*satBoost+0.45*zB).clamp(-110.0,110.0);
    final o=_toR(_Lab(lOut,aO,bO));
    lut[idx++]=_h16(o.r.clamp(0,1)); lut[idx++]=_h16(o.g.clamp(0,1)); lut[idx++]=_h16(o.b.clamp(0,1));
  }
  return lut.buffer.asUint8List();
}

// ──────────────────────────────────────────────────────────────────────────────
// Apply LUT (trilinear)
// ──────────────────────────────────────────────────────────────────────────────

_Rgb _applyLut(Uint8List bytes, _Rgb c) {
  final lut=bytes.buffer.asUint16List(); const dim=33;
  final ri=c.r*32, gi=c.g*32, bi=c.b*32;
  final r0=ri.floor().clamp(0,31), r1=(r0+1).clamp(0,32);
  final g0=gi.floor().clamp(0,31), g1=(g0+1).clamp(0,32);
  final b0=bi.floor().clamp(0,31), b1=(b0+1).clamp(0,32);
  final rf=ri-r0, gf=gi-g0, bf=bi-b0;
  _Rgb s(int r,int g,int b){ final i=(r+g*dim+b*dim*dim)*3; return _Rgb(_f16(lut[i]),_f16(lut[i+1]),_f16(lut[i+2])); }
  _Rgb lerp(_Rgb a,_Rgb b,double t)=>_Rgb(a.r+(b.r-a.r)*t, a.g+(b.g-a.g)*t, a.b+(b.b-a.b)*t);
  final c00=lerp(s(r0,g0,b0),s(r1,g0,b0),rf); final c10=lerp(s(r0,g1,b0),s(r1,g1,b0),rf);
  final c01=lerp(s(r0,g0,b1),s(r1,g0,b1),rf); final c11=lerp(s(r0,g1,b1),s(r1,g1,b1),rf);
  return lerp(lerp(c00,c10,gf),lerp(c01,c11,gf),bf);
}

img.Image _applyLutImg(img.Image src, Uint8List lutBytes) {
  final out=img.Image(width:src.width, height:src.height);
  for(int y=0;y<src.height;y++) for(int x=0;x<src.width;x++){
    final px=src.getPixel(x,y);
    final o=_applyLut(lutBytes,_Rgb(px.rNormalized.toDouble(),px.gNormalized.toDouble(),px.bNormalized.toDouble()));
    out.setPixelRgb(x,y,(o.r.clamp(0,1)*255).round(),(o.g.clamp(0,1)*255).round(),(o.b.clamp(0,1)*255).round());
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────────────
// Synthetic image generators
// ──────────────────────────────────────────────────────────────────────────────

/// Full color chart: hue × saturation grid (360 hues × 5 saturation levels)
/// + neutral gray ramp at bottom. 512×200px.
img.Image _makeColorChart() {
  const w=512, rowH=32, rows=5, rampH=40;
  final im=img.Image(width:w, height:rows*rowH+rampH);
  final sats=[0.3, 0.5, 0.7, 0.85, 1.0];
  for(int row=0;row<rows;row++){
    final sat=sats[row];
    for(int x=0;x<w;x++){
      final hue=x/w;
      // HSV → RGB
      final h6=hue*6; final i=h6.floor(); final f=h6-i;
      final p=1-sat, q=1-sat*f, t2=1-sat*(1-f);
      double r,g,b;
      switch(i%6){
        case 0: r=1; g=t2; b=p; break;
        case 1: r=q; g=1; b=p; break;
        case 2: r=p; g=1; b=t2; break;
        case 3: r=p; g=q; b=1; break;
        case 4: r=t2; g=p; b=1; break;
        default: r=1; g=p; b=q;
      }
      for(int y=row*rowH;y<(row+1)*rowH;y++){
        im.setPixelRgb(x,y,(r*255).round(),(g*255).round(),(b*255).round());
      }
    }
  }
  // Gray ramp
  for(int x=0;x<w;x++){
    final v=(x/(w-1)*255).round();
    for(int y=rows*rowH;y<rows*rowH+rampH;y++){
      im.setPixelRgb(x,y,v,v,v);
    }
  }
  return im;
}

/// Gradient test image: top=bright/highlight, bottom=dark/shadow,
/// with a horizontal hue sweep. 512×400px.
img.Image _makeGradientTest() {
  const w=512, h=400;
  final im=img.Image(width:w, height:h);
  for(int y=0;y<h;y++) for(int x=0;x<w;x++){
    final brightness=1.0-(y/h)*0.9;  // 1.0 at top, 0.1 at bottom
    final hue=x/w;
    final h6=hue*6; final i=h6.floor(); final f=h6-i;
    const sat=0.8;
    final p=brightness*(1-sat), q=brightness*(1-sat*f), t2=brightness*(1-sat*(1-f));
    final bv=brightness;
    double r,g,b;
    switch(i%6){
      case 0: r=bv; g=t2; b=p; break;
      case 1: r=q; g=bv; b=p; break;
      case 2: r=p; g=bv; b=t2; break;
      case 3: r=p; g=q; b=bv; break;
      case 4: r=t2; g=p; b=bv; break;
      default: r=bv; g=p; b=q;
    }
    im.setPixelRgb(x,y,(r*255).round(),(g*255).round(),(b*255).round());
  }
  return im;
}

/// Simulate "Fortress" style: deep cold-blue, high contrast.
/// Dark → near black with blue cast, bright → vivid sky blue.
img.Image _makeFortressStyle() {
  const w=256, h=256;
  final im=img.Image(width:w, height:h);
  final rng=math.Random(42);
  for(int y=0;y<h;y++) for(int x=0;x<w;x++){
    final ny=(y/h);
    final brightness=0.1+ny*0.85+rng.nextDouble()*0.05;  // bottom=bright(sky)
    // Strong blue cast throughout, more in highlights
    final blueCast=0.15+brightness*0.35;
    final r=(brightness*0.55).clamp(0.0,1.0);
    final g=(brightness*0.70+blueCast*0.1).clamp(0.0,1.0);
    final b=(brightness*0.95+blueCast).clamp(0.0,1.0);
    // High contrast S-curve
    double sc(double v){ return (v < 0.5) ? 2*v*v : 1-2*(1-v)*(1-v); }
    im.setPixelRgb(x, y, (sc(r)*255).toInt(), (sc(g)*255).toInt(), (sc(b)*255).toInt());
  }
  return im;
}

/// Simulate "Tram" style: warm orange shadows, teal/cool highlights.
/// Classic cinematic teal-and-orange split tone.
img.Image _makeTramStyle() {
  const w=256, h=256;
  final im=img.Image(width:w, height:h);
  final rng=math.Random(77);
  for(int y=0;y<h;y++) for(int x=0;x<w;x++){
    final brightness=(y/h*0.8+0.1+rng.nextDouble()*0.05).clamp(0.0,1.0);
    double r,g,b;
    if(brightness<0.4){
      // Warm shadow: amber/orange push
      final t=brightness/0.4;
      r=(brightness*1.3+0.12*t).clamp(0,1);
      g=(brightness*1.05+0.05*t).clamp(0,1);
      b=(brightness*0.65).clamp(0,1);
    } else {
      // Cool highlight: teal push
      final t=(brightness-0.4)/0.6;
      r=(brightness*0.85).clamp(0,1);
      g=(brightness*1.0+0.05*t).clamp(0,1);
      b=(brightness*1.1+0.12*t).clamp(0,1);
    }
    im.setPixelRgb(x,y,(r*255).round(),(g*255).round(),(b*255).round());
  }
  return im;
}

/// Simulate "Faded Matte" style: lifted blacks, reduced contrast, slight warm cast.
img.Image _makeMatteFadeStyle() {
  const w=256, h=256;
  final im=img.Image(width:w, height:h);
  final rng=math.Random(13);
  for(int y=0;y<h;y++) for(int x=0;x<w;x++){
    final brightness=(y/h*0.6+0.1+rng.nextDouble()*0.04).clamp(0.0,1.0);
    // Lift blacks (matte look): floor at 0.08
    final lifted=0.08+brightness*(1-0.08)*0.75;
    final r=(lifted*1.05).clamp(0,1);
    final g=(lifted*0.98).clamp(0,1);
    final b=(lifted*0.88).clamp(0,1);
    im.setPixelRgb(x,y,(r*255).round(),(g*255).round(),(b*255).round());
  }
  return im;
}

// ──────────────────────────────────────────────────────────────────────────────
// Compose side-by-side strip: [Label | Original | NEW | OLD | Style]
// ──────────────────────────────────────────────────────────────────────────────

img.Image _strip(String label, img.Image orig, img.Image resN, img.Image resO, img.Image style) {
  const labelW=90, gap=4, textH=18;
  final h=orig.height+textH;
  final w=labelW+orig.width+resN.width+resO.width+style.width+gap*5;
  final strip=img.Image(width:w, height:h, backgroundColor:img.ColorRgb8(20,20,20));

  // Helper: draw a text label above a panel (white letters on dark bg)
  void drawLabel(img.Image dst, int x, int y, String text, int panelW) {
    img.fillRect(dst, x1:x, y1:y, x2:x+panelW, y2:y+textH, color:img.ColorRgb8(40,40,40));
    // Simple manual pixel-font substitute — just stamp chars as colored dots
    // Use img.drawString if available, otherwise just leave the colored bar
    try {
      img.drawString(dst, text, font:img.arial14, x:x+4, y:y+2, color:img.ColorRgb8(220,220,220));
    } catch(_) {}
  }

  // Paste image
  void paste(img.Image dst, img.Image src, int ox, int oy) {
    for(int y=0;y<src.height;y++) for(int x=0;x<src.width;x++){
      final px=src.getPixel(x,y);
      dst.setPixelRgb(ox+x, oy+y, px.r.toInt(), px.g.toInt(), px.b.toInt());
    }
  }

  // Draw vertical label block on left
  img.fillRect(strip, x1:0, y1:0, x2:labelW, y2:h, color:img.ColorRgb8(30,30,30));
  try {
    img.drawString(strip, label, font:img.arial14, x:4, y:h~/2-7, color:img.ColorRgb8(255,200,80));
  } catch(_) {}

  int ox=labelW+gap;
  drawLabel(strip, ox, 0, 'ORIGINAL', orig.width); paste(strip, orig, ox, textH); ox+=orig.width+gap;
  drawLabel(strip, ox, 0, 'NEW', resN.width);      paste(strip, resN, ox, textH); ox+=resN.width+gap;
  drawLabel(strip, ox, 0, 'OLD', resO.width);      paste(strip, resO, ox, textH); ox+=resO.width+gap;
  drawLabel(strip, ox, 0, 'STYLE SRC', style.width); paste(strip, style, ox, textH);

  return strip;
}

// ──────────────────────────────────────────────────────────────────────────────
// ΔE metric
// ──────────────────────────────────────────────────────────────────────────────

(double, double) _deltaE(img.Image a, img.Image b) {
  final deltas=<double>[];
  for(int y=0;y<a.height;y++) for(int x=0;x<a.width;x++){
    final ap=a.getPixel(x,y), bp=b.getPixel(x,y);
    final la=_toL(_Rgb(ap.rNormalized.toDouble(),ap.gNormalized.toDouble(),ap.bNormalized.toDouble()));
    final lb=_toL(_Rgb(bp.rNormalized.toDouble(),bp.gNormalized.toDouble(),bp.bNormalized.toDouble()));
    final dl=la.l-lb.l, da=la.a-lb.a, db=la.b-lb.b;
    deltas.add(math.sqrt(dl*dl+da*da+db*db));
  }
  deltas.sort();
  final mean=deltas.fold(0.0,(s,v)=>s+v)/deltas.length;
  final p95=deltas[(deltas.length*0.95).floor()];
  return (mean, p95);
}

// ──────────────────────────────────────────────────────────────────────────────
// Main
// ──────────────────────────────────────────────────────────────────────────────

void main(List<String> args) {
  final outDir = args.isNotEmpty ? args[0] : 'tool/test_output';
  Directory(outDir).createSync(recursive: true);

  print('Generating synthetic test images...');
  final colorChart   = _makeColorChart();
  final gradientTest = _makeGradientTest();

  final styles = {
    'fortress_blue':   _makeFortressStyle(),
    'tram_teal_orange': _makeTramStyle(),
    'matte_fade':      _makeMatteFadeStyle(),
  };

  final results = <String>[];

  for (final entry in styles.entries) {
    final styleName = entry.key;
    final styleImg  = entry.value;

    print('\n── $styleName ──');
    print('  Extracting style profile...');
    final profile = _analyze(styleImg);

    print('  Shadow  cast: a=${profile.s.a.toStringAsFixed(1)} b=${profile.s.b.toStringAsFixed(1)}');
    print('  Midtone cast: a=${profile.m.a.toStringAsFixed(1)} b=${profile.m.b.toStringAsFixed(1)}');
    print('  Highlight cast: a=${profile.h.a.toStringAsFixed(1)} b=${profile.h.b.toStringAsFixed(1)}');

    print('  Generating LUTs...');
    final lutNew = _lutNew(profile);
    final lutOld = _lutOld(styleImg);

    // Apply to color chart
    final chartNew = _applyLutImg(colorChart, lutNew);
    final chartOld = _applyLutImg(colorChart, lutOld);

    // Apply to gradient test
    final gradNew = _applyLutImg(gradientTest, lutNew);
    final gradOld = _applyLutImg(gradientTest, lutOld);

    // Compute ΔE vs style
    // (comparing how well each result matches style's color character on a neutral image)
    final (mnNew, p95New) = _deltaE(chartNew, img.copyResize(styleImg, width:colorChart.width, height:colorChart.height));
    final (mnOld, p95Old) = _deltaE(chartOld, img.copyResize(styleImg, width:colorChart.width, height:colorChart.height));

    print('  ΔE (chart vs style)  NEW: mean=${mnNew.toStringAsFixed(2)} p95=${p95New.toStringAsFixed(2)}');
    print('  ΔE (chart vs style)  OLD: mean=${mnOld.toStringAsFixed(2)} p95=${p95Old.toStringAsFixed(2)}');
    results.add('$styleName  NEW mean=${mnNew.toStringAsFixed(2)} p95=${p95New.toStringAsFixed(2)}  |  OLD mean=${mnOld.toStringAsFixed(2)} p95=${p95Old.toStringAsFixed(2)}');

    // Save style thumbnail
    final styleThumb = img.copyResize(styleImg, width:colorChart.width, height:colorChart.height);

    // Save comparison strips
    final stripChart = _strip(styleName.replaceAll('_',' '), colorChart, chartNew, chartOld, styleThumb);
    final stripGrad  = _strip(styleName.replaceAll('_',' '), gradientTest, gradNew, gradOld,
        img.copyResize(styleImg, width:gradientTest.width, height:gradientTest.height));

    final chartPath = '$outDir/${styleName}_chart.png';
    final gradPath  = '$outDir/${styleName}_gradient.png';
    File(chartPath).writeAsBytesSync(img.encodePng(stripChart));
    File(gradPath).writeAsBytesSync(img.encodePng(stripGrad));
    print('  Saved: $chartPath');
    print('  Saved: $gradPath');
  }

  // Save the original test images for reference
  File('$outDir/_original_colorchart.png').writeAsBytesSync(img.encodePng(colorChart));
  File('$outDir/_original_gradient.png').writeAsBytesSync(img.encodePng(gradientTest));

  print('\n══════════════════════════════════════════');
  print('Summary');
  print('══════════════════════════════════════════');
  for (final r in results) print('  $r');
  print('\nOutput folder: $outDir');
  print('Open the PNG files to compare NEW vs OLD visually.');
  print('\nReading guide:');
  print('  ORIGINAL  = test color chart (input)');
  print('  NEW       = current algorithm (per-channel curves + zone tint)');
  print('  OLD       = previous algorithm (Lab-only zone push + satBoost)');
  print('  STYLE SRC = the style image the filter was extracted from');
  print('\nGood filter: NEW should look closer to STYLE SRC than OLD,');
  print('  while keeping vivid colors in ORIGINAL vivid (not washed).');
}
