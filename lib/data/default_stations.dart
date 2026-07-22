/// 기본 조위관측소 목록 (오프라인/최초 실행용).
///
/// 실제 코드·좌표는 앱 시작 시 KHOA 관측소 목록 API(ObsServiceObj)로
/// 갱신·검증된다. 여기 목록은 API 키가 없거나 네트워크가 안 될 때의
/// 폴백이며, 이름 기준으로 라이브 목록과 병합된다.
library;

import '../models/models.dart';

const List<Station> defaultStations = [
  Station(code: 'DT_0001', name: '인천', lat: 37.452, lon: 126.592),
  Station(code: 'DT_0002', name: '평택', lat: 36.966, lon: 126.822),
  Station(code: 'DT_0008', name: '안산', lat: 37.192, lon: 126.647),
  Station(code: 'DT_0017', name: '대산', lat: 37.007, lon: 126.353),
  Station(code: 'DT_0025', name: '보령', lat: 36.406, lon: 126.486),
  Station(code: 'DT_0018', name: '군산', lat: 35.975, lon: 126.563),
  Station(code: 'DT_0007', name: '목포', lat: 34.780, lon: 126.375),
  Station(code: 'DT_0026', name: '완도', lat: 34.315, lon: 126.759),
  Station(code: 'DT_0016', name: '여수', lat: 34.747, lon: 127.765),
  Station(code: 'DT_0014', name: '통영', lat: 34.827, lon: 128.434),
  Station(code: 'DT_0005', name: '부산', lat: 35.096, lon: 129.035),
  Station(code: 'DT_0004', name: '제주', lat: 33.527, lon: 126.543),
  Station(code: 'DT_0010', name: '서귀포', lat: 33.240, lon: 126.561),
  Station(code: 'DT_0006', name: '묵호', lat: 37.550, lon: 129.116),
  Station(code: 'DT_0012', name: '속초', lat: 38.207, lon: 128.594),
  Station(code: 'DT_0013', name: '울릉도', lat: 37.491, lon: 130.913),
];
