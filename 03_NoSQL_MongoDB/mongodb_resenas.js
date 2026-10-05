/* =====================================================================
   mongodb_resenas.js  -  Colecciones NoSQL de la cevichería (MongoDB / mongosh)
   1) CatalogoMenu  : carta con atributos variables 
   2) Resenas       : 5 200 reseñas semiestructuradas importadas desde ../00_Datos/Externos/Resenas_Clientes.jsonl
   ===================================================================== */

/* ---------------- CatalogoMenu: CRUD ---------------- */
db.createCollection("CatalogoMenu")
// CREATE
db.CatalogoMenu.insertMany([
  { plato_principal: "Ceviche Clásico", precio_base: 28.00, ingredientes_extra: ["Chifles", "Camote extra"], alergenos: ["pescado"],
    resenas_clientes: [{ usuario: "juanito99", puntuacion: 5, comentario: "El pescado súper fresco." }] },
  { plato_principal: "Leche de Tigre Especial", precio_base: 24.00, temporada: "verano", alergenos: ["pescado", "mariscos"] },
  { plato_principal: "Ceviche Vegetariano", precio_base: 24.00, vegetariano: true, ingredientes_extra: ["Palta"] }])
// READ
db.CatalogoMenu.find({ ingredientes_extra: "Chifles" })
db.CatalogoMenu.find({ alergenos: { $in: ["mariscos"] } }, { plato_principal: 1, precio_base: 1, _id: 0 })
// UPDATE
db.CatalogoMenu.updateOne({ plato_principal: "Ceviche Clásico" }, { $set: { precio_base: 26.00 }, $push: { ingredientes_extra: "Cancha" } })
// DELETE
db.CatalogoMenu.deleteOne({ plato_principal: "Ceviche Vegetariano" })

/* ---------------- Reseas: consultas sobre 5 200 documentos con campos variables ---------------- */
db.Resenas.countDocuments()                                              // 5200
db.Resenas.createIndex({ plato: 1, puntuacion: -1 })                     // acelera filtros por plato/puntuación
db.Resenas.createIndex({ fecha: 1 })
// READ con campos opcionales
db.Resenas.find({ puntuacion: { $lte: 2 }, respuesta_local: { $exists: false } }).limit(5)
db.Resenas.find({ etiquetas: { $all: ["fresco", "sabor"] } }).limit(5)
db.Resenas.find({ "visita.ocasion": "Cumpleaños" }).limit(5)
// AGGREGATE: puntuación media y número de reseñas por plato (top 10)
db.Resenas.aggregate([
  { $group: { _id: "$plato", promedio: { $avg: "$puntuacion" }, resenas: { $sum: 1 } } },
  { $match: { resenas: { $gte: 50 } } }, { $sort: { promedio: -1 } }, { $limit: 10 }])
// AGGREGATE: distribución por fuente
db.Resenas.aggregate([{ $group: { _id: "$fuente", n: { $sum: 1 }, prom: { $avg: "$puntuacion" } } }, { $sort: { n: -1 } }])
// UPDATE masivo: marcar como "atendidas" las reseñas negativas con respuesta del local
db.Resenas.updateMany({ puntuacion: { $lte: 2 }, respuesta_local: { $exists: true } }, { $set: { atendida: true } })
// DELETE: retirar reseñas de prueba
db.Resenas.deleteMany({ _id: { $gt: 5200 } })
