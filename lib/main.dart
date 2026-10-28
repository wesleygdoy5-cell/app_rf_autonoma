// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'propagation.dart';

void main() => runApp(const MyApp());

// ---------------- Utilidades ----------------

String fmtNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

Color rssiColor(double rssi) {
  if (rssi >= -65) return Colors.red;
  if (rssi >= -80) return Colors.orange;
  if (rssi >= -95) return Colors.yellow;
  if (rssi >= -110) return Colors.green;
  return Colors.blue;
}

class TechProfile {
  final double freq;
  final double power;
  final double gtx;
  const TechProfile(this.freq, this.power, this.gtx);
}

const Map<String, TechProfile> kTechProfiles = {
  'WiFi 2.4 GHz': TechProfile(2400, 20, 3),
  'WiFi 5 GHz': TechProfile(5200, 23, 4),
  'LTE/4G 700 MHz': TechProfile(700, 43, 15),
  'LTE/4G 1800 MHz': TechProfile(1800, 43, 15),
  'LoRa 915 MHz': TechProfile(915, 20, 2),
  'Sigfox 902 MHz': TechProfile(902, 22, 3),
};

/// Configuración del estudio. Valores por defecto = prueba de concepto
/// (WiFi 2.4 GHz, Log-Distance, urbano, radio 2 km).
class StudyConfig {
  String technology = 'WiFi 2.4 GHz';
  PropagationModel model = PropagationModel.logDistance;
  double frequencyMhz = 2400;
  double txPowerDbm = 20;
  double txGainDbi = 3;
  double rxGainDbi = 4;
  double radiusKm = 2.0;
  double exponent = 3.0;
  double txHeightM = 30;
  double rxHeightM = 1.5;
  Environment environment = Environment.urbano;
  CitySize citySize = CitySize.mediana;

  StudyConfig();

  StudyConfig clone() => StudyConfig()
    ..technology = technology
    ..model = model
    ..frequencyMhz = frequencyMhz
    ..txPowerDbm = txPowerDbm
    ..txGainDbi = txGainDbi
    ..rxGainDbi = rxGainDbi
    ..radiusKm = radiusKm
    ..exponent = exponent
    ..txHeightM = txHeightM
    ..rxHeightM = rxHeightM
    ..environment = environment
    ..citySize = citySize;

  PropagationParams toParams() => PropagationParams(
        frequencyMhz: frequencyMhz,
        txHeightM: txHeightM,
        rxHeightM: rxHeightM,
        environment: environment,
        citySize: citySize,
        pathLossExponent: exponent,
      );
}

// ---------------- App ----------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Planificador Radioeléctrico Móvil',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const CoberturaRFScreen(),
    );
  }
}

class CoberturaRFScreen extends StatefulWidget {
  const CoberturaRFScreen({super.key});

  @override
  State<CoberturaRFScreen> createState() => _CoberturaRFScreenState();
}

class _CoberturaRFScreenState extends State<CoberturaRFScreen> {
  LatLng _tx = const LatLng(-0.176774, -78.485212);
  StudyConfig _cfg = StudyConfig();
  CoverageResult? _result;
  List<CircleMarker> _circles = [];

  void _calculate() {
    final r = computeCoverage(
      txLat: _tx.latitude,
      txLon: _tx.longitude,
      radiusKm: _cfg.radiusKm,
      txPowerDbm: _cfg.txPowerDbm,
      txGainDbi: _cfg.txGainDbi,
      rxGainDbi: _cfg.rxGainDbi,
      model: _cfg.model,
      params: _cfg.toParams(),
    );
    final circles = r.cells
        .map((c) => CircleMarker(
              point: LatLng(c.lat, c.lon),
              radius: r.cellRadiusM,
              useRadiusInMeter: true,
              color: rssiColor(c.rssiDbm).withAlpha(150),
            ))
        .toList();
    setState(() {
      _result = r;
      _circles = circles;
    });
  }

  Future<void> _openConfig() async {
    final updated = await showModalBottomSheet<StudyConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConfigSheet(initial: _cfg.clone()),
    );
    if (updated != null) {
      setState(() => _cfg = updated);
      _calculate();
    }
  }

  Future<void> _exportPdf() async {
    final r = _result;
    if (r == null) return;
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Informe Técnico - Planificador Radioeléctrico',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Fecha: ${DateTime.now().toIso8601String()}'),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text('Parámetros del estudio de cobertura RF:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Bullet(text: 'Tecnología: ${_cfg.technology}'),
              pw.Bullet(text: 'Modelo de propagación: ${_cfg.model.label}'),
              pw.Bullet(text: 'Frecuencia: ${fmtNum(_cfg.frequencyMhz)} MHz'),
              pw.Bullet(text: 'Potencia Tx: ${fmtNum(_cfg.txPowerDbm)} dBm'),
              pw.Bullet(text: 'Ganancia Tx: ${fmtNum(_cfg.txGainDbi)} dBi'),
              pw.Bullet(text: 'Ganancia Rx: ${fmtNum(_cfg.rxGainDbi)} dBi'),
              pw.Bullet(
                  text:
                      'Ubicación Tx: Lat ${_tx.latitude.toStringAsFixed(6)}, Lon ${_tx.longitude.toStringAsFixed(6)}'),
              pw.Bullet(text: 'Radio de estudio: ${fmtNum(_cfg.radiusKm)} km'),
              if (_cfg.model == PropagationModel.logDistance)
                pw.Bullet(text: 'Exponente de pérdida (n): ${fmtNum(_cfg.exponent)}'),
              if (_cfg.model == PropagationModel.okumuraHata ||
                  _cfg.model == PropagationModel.cost231Hata) ...[
                pw.Bullet(text: 'Altura Tx: ${fmtNum(_cfg.txHeightM)} m'),
                pw.Bullet(text: 'Altura Rx: ${fmtNum(_cfg.rxHeightM)} m'),
                pw.Bullet(text: 'Entorno: ${_cfg.environment.label}'),
                pw.Bullet(text: 'Tamaño de ciudad: ${_cfg.citySize.label}'),
              ],
              pw.SizedBox(height: 15),
              pw.Text('Resultados de la simulación:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Bullet(
                  text:
                      'RSSI máximo (cerca del Tx): ${r.maxRssi.toStringAsFixed(2)} dBm'),
              pw.Bullet(
                  text:
                      'RSSI mínimo (borde): ${r.minRssi.toStringAsFixed(2)} dBm'),
              pw.Bullet(text: 'Celdas calculadas: ${r.cells.length}'),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(
      name: 'informe_cobertura_rf.pdf',
      onLayout: (format) async => pdf.save(),
    );
  }

  Widget _panel(List<String> warnings) {
    final r = _result;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_cfg.technology} · ${_cfg.model.label}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 2),
            Text(
                '${fmtNum(_cfg.frequencyMhz)} MHz · ${fmtNum(_cfg.txPowerDbm)} dBm · radio ${fmtNum(_cfg.radiusKm)} km',
                style: const TextStyle(fontSize: 12)),
            Text(
                'Tx: ${_tx.latitude.toStringAsFixed(5)}, ${_tx.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (r != null)
              Text(
                  'RSSI máx ${r.maxRssi.toStringAsFixed(1)} dBm · mín ${r.minRssi.toStringAsFixed(1)} dBm · ${r.cells.length} celdas',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            for (final w in warnings)
              Text('⚠ $w',
                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openConfig,
                    icon: const Icon(Icons.tune),
                    label: const Text('Configurar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _calculate,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Calcular'),
                  ),
                ),
                if (r != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    color: Colors.red.shade700,
                    tooltip: 'Exportar PDF',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            const Text('Mapa © OpenStreetMap contributors',
                style: TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warnings =
        rangeWarnings(_cfg.model, _cfg.toParams(), _cfg.radiusKm);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobertura RF'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_input_antenna),
            tooltip: 'Configurar estudio',
            onPressed: _openConfig,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _tx,
              initialZoom: 14.0,
              onTap: (tapPosition, point) {
                setState(() {
                  _tx = point;
                  _result = null;
                  _circles = [];
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app_rf_autonoma',
              ),
              CircleLayer(circles: _circles),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _tx,
                    width: 45,
                    height: 45,
                    child: const Icon(Icons.location_on,
                        color: Colors.blueAccent, size: 42),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(220),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Toca el mapa para ubicar el transmisor',
                  style: TextStyle(fontSize: 11)),
            ),
          ),
          if (_result != null)
            Positioned(top: 8, right: 8, child: const _Legend()),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: SafeArea(child: _panel(warnings)),
          ),
        ],
      ),
    );
  }
}

// ---------------- Leyenda ----------------

class _Legend extends StatelessWidget {
  const _Legend();

  Widget _row(Color c, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, color: c),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RSSI (dBm)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 4),
          _row(Colors.red, '≥ -65'),
          _row(Colors.orange, '-65 a -80'),
          _row(Colors.yellow, '-80 a -95'),
          _row(Colors.green, '-95 a -110'),
          _row(Colors.blue, '< -110'),
        ],
      ),
    );
  }
}

// ---------------- Hoja de configuración ----------------

class ConfigSheet extends StatefulWidget {
  final StudyConfig initial;
  const ConfigSheet({super.key, required this.initial});

  @override
  State<ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<ConfigSheet> {
  late StudyConfig cfg;
  late final TextEditingController _freq;
  late final TextEditingController _power;
  late final TextEditingController _gtx;
  late final TextEditingController _grx;
  late final TextEditingController _radius;
  late final TextEditingController _n;
  late final TextEditingController _hb;
  late final TextEditingController _hm;

  @override
  void initState() {
    super.initState();
    cfg = widget.initial;
    _freq = TextEditingController(text: fmtNum(cfg.frequencyMhz));
    _power = TextEditingController(text: fmtNum(cfg.txPowerDbm));
    _gtx = TextEditingController(text: fmtNum(cfg.txGainDbi));
    _grx = TextEditingController(text: fmtNum(cfg.rxGainDbi));
    _radius = TextEditingController(text: fmtNum(cfg.radiusKm));
    _n = TextEditingController(text: fmtNum(cfg.exponent));
    _hb = TextEditingController(text: fmtNum(cfg.txHeightM));
    _hm = TextEditingController(text: fmtNum(cfg.rxHeightM));
  }

  @override
  void dispose() {
    for (final c in [_freq, _power, _gtx, _grx, _radius, _n, _hb, _hm]) {
      c.dispose();
    }
    super.dispose();
  }

  double _read(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;

  /// Copia los valores de los campos a cfg.
  void _apply() {
    cfg.frequencyMhz = _read(_freq, cfg.frequencyMhz);
    cfg.txPowerDbm = _read(_power, cfg.txPowerDbm);
    cfg.txGainDbi = _read(_gtx, cfg.txGainDbi);
    cfg.rxGainDbi = _read(_grx, cfg.rxGainDbi);
    cfg.radiusKm = _read(_radius, cfg.radiusKm).clamp(0.05, 50.0).toDouble();
    cfg.exponent = _read(_n, cfg.exponent);
    cfg.txHeightM = _read(_hb, cfg.txHeightM);
    cfg.rxHeightM = _read(_hm, cfg.rxHeightM);
  }

  void _selectTech(String tech) {
    final p = kTechProfiles[tech];
    if (p == null) return;
    setState(() {
      cfg.technology = tech;
      _freq.text = fmtNum(p.freq);
      _power.text = fmtNum(p.power);
      _gtx.text = fmtNum(p.gtx);
    });
  }

  Widget _numField(String label, TextEditingController c) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(
            decimal: true, signed: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    _apply();
    final warnings = rangeWarnings(cfg.model, cfg.toParams(), cfg.radiusKm);
    final isHata = cfg.model == PropagationModel.okumuraHata ||
        cfg.model == PropagationModel.cost231Hata;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configurar estudio y modelo RF',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            _label('Tecnología'),
            DropdownButtonFormField<String>(
              value: cfg.technology,
              isExpanded: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
              items: kTechProfiles.keys
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _selectTech(v);
              },
            ),
            _label('Modelo de propagación'),
            DropdownButtonFormField<PropagationModel>(
              value: cfg.model,
              isExpanded: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
              items: PropagationModel.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) => setState(() => cfg.model = v!),
            ),
            const SizedBox(height: 10),
            if (cfg.model == PropagationModel.freeSpace)
              const Text(
                  'Ideal para enlaces con línea de vista (LOS). Solo usa frecuencia y distancia.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            if (cfg.model == PropagationModel.logDistance) ...[
              const Text(
                  'Modelo empírico: requiere el exponente de pérdida n según el entorno (típico 2.7 a 4.0).',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              _numField('Exponente de pérdida n', _n),
            ],
            if (isHata) ...[
              Row(
                children: [
                  Expanded(child: _numField('Altura Tx (m)', _hb)),
                  const SizedBox(width: 8),
                  Expanded(child: _numField('Altura Rx (m)', _hm)),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Environment>(
                value: cfg.environment,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Entorno',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: Environment.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                    .toList(),
                onChanged: (v) => setState(() => cfg.environment = v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<CitySize>(
                value: cfg.citySize,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Tamaño de ciudad',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: CitySize.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                    .toList(),
                onChanged: (v) => setState(() => cfg.citySize = v!),
              ),
            ],
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('⚠ $w',
                    style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ),
            _label('Parámetros comunes'),
            Row(
              children: [
                Expanded(child: _numField('Frecuencia (MHz)', _freq)),
                const SizedBox(width: 8),
                Expanded(child: _numField('Potencia Tx (dBm)', _power)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _numField('Ganancia Tx (dBi)', _gtx)),
                const SizedBox(width: 8),
                Expanded(child: _numField('Ganancia Rx (dBi)', _grx)),
              ],
            ),
            const SizedBox(height: 8),
            _numField('Radio de estudio (km)', _radius),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _apply();
                      Navigator.pop(context, cfg);
                    },
                    child: const Text('Generar mapa'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}