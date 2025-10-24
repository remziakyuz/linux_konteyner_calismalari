<?php
$host = getenv('DB_HOST') ?: 'mariadb';
$user = getenv('DB_USER') ?: 'root';
$pass = getenv('DB_PASSWORD') ?: 'TA3RDA';
$db   = getenv('DB_NAME') ?: 'appdb';
$dsn = "mysql:host=$host;dbname=$db;charset=utf8mb4";
try {
  $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Exception $e) { die("DB bağlanamıyor: " . $e->getMessage()); }

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $stmt = $pdo->prepare("INSERT INTO guestbook(isim, mesaj) VALUES(?, ?)");
  $stmt->execute([$_POST['isim'], $_POST['mesaj']]);
  header("Location: /"); exit;
}
$rows = $pdo->query("SELECT isim, mesaj, ts FROM guestbook ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
?>
<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><title>Guestbook</title></head>
<body style="font-family: sans-serif">
<h2>🐧 Guestbook</h2>
<form method="post">
  İsim: <input name="isim" required>  Mesaj: <input name="mesaj" required>
  <button type="submit">Gönder</button>
</form>
<hr>
<?php foreach ($rows as $r): ?>
  <p><strong><?= htmlspecialchars($r['isim']) ?></strong> – <?= htmlspecialchars($r['mesaj']) ?> <em>(<?= $r['ts'] ?>)</em></p>
<?php endforeach; ?>
</body></html>
