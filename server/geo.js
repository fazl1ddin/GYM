// Геозона: расстояние между двумя точками (формула гаверсинусов), метры.

export function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000; // радиус Земли, м
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// Внутри ли точка радиуса рабочего места. Возвращает {inside, distance}.
export function checkGeozone(workplace, lat, lng) {
  if (!workplace || workplace.lat == null || workplace.lng == null) {
    return { inside: false, distance: null, reason: 'workplace_no_coords' };
  }
  if (lat == null || lng == null) {
    return { inside: false, distance: null, reason: 'no_location' };
  }
  const distance = haversineMeters(workplace.lat, workplace.lng, lat, lng);
  return { inside: distance <= workplace.radius_m, distance };
}
