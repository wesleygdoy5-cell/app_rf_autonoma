// lib/propagation.dart
// ---------------------------------------------------------------
// Modelos de propagación y cálculo de cobertura (Dart puro, sin Flutter).
// Equivale a los modelos clásicos de la PaaS: Free Space, Log-Distance,
// Okumura-Hata y COST-231 Hata. Distancias en km, frecuencias en MHz.
// ---------------------------------------------------------------

import 'dart:math';

double _log10(double x) => log(x) / ln10;

enum PropagationModel {
  freeSpace('Free Space'),
  logDistance('Log-Distance'),
  okumuraHata('Okumura-Hata'),
  cost231Hata('COST-231 Hata');

  final String label;
  const PropagationModel(this.label);
}

enum Environment {
  urbano('Urbano'),
  suburbano('Suburbano'),
  rural('Rural');

  final String label;
  const Environment(this.label);
}

enum CitySize {
  pequena('Pequeña'),
  mediana('Mediana'),
  grande('Grande');

  final String label;
  const CitySize(this.label);
}

class PropagationParams {
  final double frequencyMhz;
  final double txHeightM;
  final double rxHeightM;
  final Environment environment;
  final CitySize citySize;
  final double pathLossExponent;
  final double referenceDistanceKm;

  /// Si es null, Log-Distance usa la pérdida de espacio libre a d0.
  final double? referenceLossDb;

  const PropagationParams({
    required this.frequencyMhz,
    this.txHeightM = 30.0,
    this.rxHeightM = 1.5,
    this.environment = Environment.urbano,
    this.citySize = CitySize.mediana,
    this.pathLossExponent = 3.0,
    this.referenceDistanceKm = 0.001,
    this.referenceLossDb,
  });
}

// ---------------- Fórmulas ----------------

/// FSPL (dB) = 32.45 + 20 log10(f_MHz) + 20 log10(d_km)
double freeSpaceLoss(double fMhz, double dKm) =>
    32.45 + 20 * _log10(fMhz) + 20 * _log10(dKm);

/// PL(d) = PL(d0) + 10 n log10(d / d0)
double logDistanceLoss(PropagationParams p, double dKm) {
  final d0 = p.referenceDistanceKm;
  final pl0 = p.referenceLossDb ?? freeSpaceLoss(p.frequencyMhz, d0);
  final d = dKm < d0 ? d0 : dKm; // no extrapolar por debajo de d0
  return pl0 + 10 * p.pathLossExponent * _log10(d / d0);
}

/// Corrección de antena móvil para ciudad pequeña/mediana.
double _aHmMedium(double fMhz, double hm) =>
    (1.1 * _log10(fMhz) - 0.7) * hm - (1.56 * _log10(fMhz) - 0.8);

/// Corrección de antena móvil para ciudad grande (Okumura-Hata).
double _aHmLarge(double fMhz, double hm) {
  if (fMhz <= 300) {
    final x = _log10(1.54 * hm);
    return 8.29 * x * x - 1.1;
  }
  final x = _log10(11.75 * hm);
  return 3.2 * x * x - 4.97;
}

double okumuraHataLoss(PropagationParams p, double dKm) {
  final f = p.frequencyMhz;
  final hb = p.txHeightM;
  final lf = _log10(f);
  final aHm = (p.environment == Environment.urbano &&
          p.citySize == CitySize.grande)
      ? _aHmLarge(f, p.rxHeightM)
      : _aHmMedium(f, p.rxHeightM);

  final urban = 69.55 +
      26.16 * lf -
      13.82 * _log10(hb) -
      aHm +
      (44.9 - 6.55 * _log10(hb)) * _log10(dKm);

  if (p.environment == Environment.suburbano) {
    final x = _log10(f / 28);
    return urban - 2 * x * x - 5.4;
  }
  if (p.environment == Environment.rural) {
    return urban - 4.78 * lf * lf + 18.33 * lf - 40.94;
  }
  return urban;
}

double cost231HataLoss(PropagationParams p, double dKm) {
  final f = p.frequencyMhz;
  final hb = p.txHeightM;
  // Cm = 3 dB solo en centros metropolitanos.
  final cm = (p.environment == Environment.urbano &&
          p.citySize == CitySize.grande)
      ? 3.0
      : 0.0;
  return 46.3 +
      33.9 * _log10(f) -
      13.82 * _log10(hb) -
      _aHmMedium(f, p.rxHeightM) +
      (44.9 - 6.55 * _log10(hb)) * _log10(dKm) +
      cm;
}

/// Pérdida de trayecto (dB) según el modelo elegido.
double pathLoss(PropagationModel model, PropagationParams p, double dKm) {
  final d = dKm < 0.001 ? 0.001 : dKm;
  switch (model) {
    case PropagationModel.freeSpace:
      return freeSpaceLoss(p.frequencyMhz, d);
    case PropagationModel.logDistance:
      return logDistanceLoss(p, d);
    case PropagationModel.okumuraHata:
      return okumuraHataLoss(p, d);
    case PropagationModel.cost231Hata:
      return cost231HataLoss(p, d);
  }
}

/// Avisos de rango de validez nominal de Hata / COST-231.
List<String> rangeWarnings(
  PropagationModel model,
  PropagationParams p,
  double radiusKm,
) {
  final out = <String>[];
  if (model == PropagationModel.okumuraHata) {
    if (p.frequencyMhz < 150 || p.frequencyMhz > 1500) {
      out.add('Okumura-Hata es válido de 150 a 1500 MHz (usas ${p.frequencyMhz.toStringAsFixed(0)}).');
    }
  } else if (model == PropagationModel.cost231Hata) {
    if (p.frequencyMhz < 1500 || p.frequencyMhz > 2000) {
      out.add('COST-231 es válido de 1500 a 2000 MHz (usas ${p.frequencyMhz.toStringAsFixed(0)}).');
    }
  } else {
    return out;
  }
  if (p.txHeightM < 30 || p.txHeightM > 200) {
    out.add('Altura Tx fuera de 30–200 m.');
  }
  if (p.rxHeightM < 1 || p.rxHeightM > 10) {
    out.add('Altura Rx fuera de 1–10 m.');
  }
  if (radiusKm < 1) {
    out.add('Radio < 1 km: el modelo es válido de 1 a 20 km.');
  } else if (radiusKm > 20) {
    out.add('Radio > 20 km: fuera del rango del modelo.');
  } else {
    out.add('Las celdas a menos de 1 km quedan fuera del rango nominal (1–20 km).');
  }
  return out;
}

// ---------------- Cobertura ----------------

class CoverageCell {
  final double lat;
  final double lon;
  final double distKm;
  final double rssiDbm;
  const CoverageCell(this.lat, this.lon, this.distKm, this.rssiDbm);
}

class CoverageResult {
  final List<CoverageCell> cells;
  final double maxRssi;
  final double minRssi;

  /// Radio (m) de cada círculo para que las celdas se solapen sin huecos.
  final double cellRadiusM;

  const CoverageResult(this.cells, this.maxRssi, this.minRssi, this.cellRadiusM);
}

/// Rejilla cuadrada centrada en el Tx; descarta celdas fuera del radio.
/// RSSI = Ptx + Gtx + Grx - pérdidas_sistema - PL(d)
CoverageResult computeCoverage({
  required double txLat,
  required double txLon,
  required double radiusKm,
  required double txPowerDbm,
  required double txGainDbi,
  required double rxGainDbi,
  required PropagationModel model,
  required PropagationParams params,
  double systemLossesDb = 0.0,
  int gridSize = 41,
}) {
  const kmPerDegLat = 111.32;
  final cosLat = max(cos(txLat * pi / 180), 1e-6);
  final kmPerDegLon = kmPerDegLat * cosLat;
  final step = 2 * radiusKm / (gridSize - 1);

  final cells = <CoverageCell>[];
  var maxR = double.negativeInfinity;
  var minR = double.infinity;

  for (var i = 0; i < gridSize; i++) {
    final dy = -radiusKm + i * step;
    for (var j = 0; j < gridSize; j++) {
      final dx = -radiusKm + j * step;
      final d = sqrt(dx * dx + dy * dy);
      if (d > radiusKm) continue;

      final loss = pathLoss(model, params, d);
      if (!loss.isFinite) continue;

      final rssi = txPowerDbm + txGainDbi + rxGainDbi - systemLossesDb - loss;
      if (rssi > maxR) maxR = rssi;
      if (rssi < minR) minR = rssi;

      cells.add(CoverageCell(
        txLat + dy / kmPerDegLat,
        txLon + dx / kmPerDegLon,
        d,
        rssi,
      ));
    }
  }

  return CoverageResult(cells, maxR, minR, step * 1000 * 0.72);
}