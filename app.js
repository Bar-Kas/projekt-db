const express = require("express");
const { Pool } = require("pg");
const bodyParser = require("body-parser");
const session = require("express-session");
const PDFDocument = require("pdfkit");
const moment = require("moment");
const path = require("path");
const fs = require("fs");
const multer = require("multer");
const QRCode = require("qrcode");

const app = express();
const port = 3000;

// --- KONFIGURACJA ---
app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "views"));

app.use(express.static(path.join(__dirname, "public")));
app.use("/uploads", express.static(path.join(__dirname, "public", "uploads")));
app.use(bodyParser.urlencoded({ extended: true }));

// Konfiguracja Bazy Danych
const pool = new Pool({
  user: "postgres",
  host: "localhost",
  database: "teatr_db",
  password: "password", // Upewnij się, że hasło jest poprawne
  port: 5432,
});

// Konfiguracja Multer (Upload Plakatów)
const uploadDir = path.join(__dirname, "public", "images");
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, "public/images/"),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, "poster-" + Date.now() + ext);
  },
});
const upload = multer({ storage: storage });

// Sesja
app.use(
  session({
    secret: "sekret_akademicki",
    resave: false,
    saveUninitialized: true,
  }),
);

// Middleware użytkownika (Symulacja logowania)
app.use(async (req, res, next) => {
  if (!req.session.user) {
    try {
      // Dynamicznie pobiera z bazy rzeczywiste ID Administratora
      const userRes = await pool.query(
        "SELECT u.person_id, u.role, p.first_name, p.last_name FROM users u JOIN persons p ON u.person_id = p.id WHERE u.role = 'admin' LIMIT 1",
      );
      if (userRes.rows.length > 0) {
        const dbUser = userRes.rows[0];
        req.session.user = {
          id: dbUser.person_id,
          role: dbUser.role,
          name: `${dbUser.first_name} ${dbUser.last_name}`,
        };
      }
    } catch (e) {
      console.error("Błąd logowania:", e);
    }
  }
  res.locals.user = req.session.user;
  next();
});
// ==========================================
// 1. ZAAWANSOWANE SQL (WYMOGI PROJEKTOWE - Pkt 5)
// ==========================================

app.get("/admin/stats", async (req, res) => {
  try {
    const stats = {};

    // A. HAVING & GROUP BY
    stats.richGenres = await pool.query(`
      SELECT g.name, AVG(t.final_price) as avg_price
      FROM genres g
      JOIN spectacles s ON s.genre_id = g.id
      JOIN seances se ON se.spectacle_id = s.id
      JOIN reservations r ON r.seance_id = se.id
      JOIN tickets t ON t.reservation_id = r.id
      GROUP BY g.name
      HAVING AVG(t.final_price) > 30
    `);

    // B. EXISTS & SKORELOWANE
    stats.dramaActors = await pool.query(`
      SELECT p.first_name, p.last_name 
      FROM actors a
      JOIN persons p ON a.person_id = p.id
      WHERE EXISTS (
        SELECT 1 FROM spectacle_actors sa
        JOIN spectacles s ON sa.spectacle_id = s.id
        JOIN genres g ON s.genre_id = g.id
        WHERE sa.actor_id = a.person_id AND g.name = 'Dramat'
      )
    `);

    // C. ALL
    stats.longSpectacles = await pool.query(`
      SELECT title, duration_minutes 
      FROM spectacles
      WHERE duration_minutes > ALL (
        SELECT duration_minutes FROM spectacles 
        JOIN genres ON spectacles.genre_id = genres.id 
        WHERE genres.name = 'Musical'
      )
    `);

    // D. PODZAPYTANIE NIESKORELOWANE
    stats.highEarners = await pool.query(`
      SELECT p.first_name, p.last_name, e.salary 
      FROM employees e
      JOIN persons p ON e.person_id = p.id
      WHERE e.salary > (SELECT AVG(salary) FROM employees)
    `);

    res.render("admin_stats", { stats });
  } catch (err) {
    res.status(500).send("Błąd SQL: " + err.message);
  }
});

// ==========================================
// 2. RAPORTOWANIE (PDF - Pkt 6 i 7)
// ==========================================

app.get("/admin/reports", (req, res) => {
  res.render("admin_reports");
});

app.post("/admin/reports/generate", async (req, res) => {
  const { reportType, dateFrom, dateTo, minAmount } = req.body;
  const doc = new PDFDocument({ margin: 50 });

  // 1. Odbiór i parsowanie KRYTERIÓW (Spełnia Pkt 6b.2)
  const start = dateFrom ? dateFrom : "1970-01-01";
  const end = dateTo ? dateTo + " 23:59:59" : "2100-12-31 23:59:59";
  const minVal = parseFloat(minAmount) || 0;

  const filename = `Raport_${reportType}_${Date.now()}.pdf`;
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);
  doc.pipe(res);

  const fontPath = path.join(__dirname, "fonts", "Roboto-Regular.ttf");
  if (fs.existsSync(fontPath)) doc.font(fontPath);

  doc.fontSize(20).text("RAPORT PDF TEATR", { align: "center" });
  doc.moveDown(0.5);
  doc
    .fontSize(10)
    .fillColor("gray")
    .text(
      `Kryteria: Od ${start.split(" ")[0]} | Do ${end.split(" ")[0]} | Min. Kwota: ${minVal} PLN`,
      { align: "center" },
    );
  doc.moveDown(2);
  doc.fillColor("black");

  try {
    // =========================================================================
    // RAPORT 1: Z GRUPOWANIEM (Pkt 6b.3)
    // =========================================================================
    if (reportType === "sales_grouped") {
      doc
        .fontSize(16)
        .text("Analiza Finansowa: Sprzedaż wg Gatunków", { underline: true })
        .moveDown();

      const salesQuery = `
        SELECT g.name as genre, s.title, COUNT(t.id) as tickets, COALESCE(SUM(t.final_price), 0) as income
        FROM genres g
        JOIN spectacles s ON s.genre_id = g.id
        LEFT JOIN seances se ON se.spectacle_id = s.id
        LEFT JOIN reservations r ON r.seance_id = se.id
        LEFT JOIN tickets t ON t.reservation_id = r.id
        WHERE se.start_time >= $1 AND se.start_time <= $2
        GROUP BY g.name, s.title
        HAVING COALESCE(SUM(t.final_price), 0) >= $3
        ORDER BY g.name, income DESC
      `;
      // Użycie 3 kryteriów w SQL
      const salesData = await pool.query(salesQuery, [start, end, minVal]);

      let totalRevenue = 0;
      let currentGenre = "";

      if (salesData.rows.length === 0)
        doc.text("Brak danych dla podanych kryteriów.");

      salesData.rows.forEach((row) => {
        totalRevenue += parseFloat(row.income);
        if (row.genre !== currentGenre) {
          currentGenre = row.genre;
          doc
            .moveDown(0.5)
            .fontSize(14)
            .fillColor("blue")
            .text(`Kategoria: ${currentGenre}`);
          doc.fillColor("black").fontSize(12);
        }
        doc.text(
          ` - ${row.title}: ${row.tickets} biletów, Przychód: ${parseFloat(row.income).toFixed(2)} PLN`,
        );
      });

      doc
        .moveDown(2)
        .fontSize(14)
        .font(fs.existsSync(fontPath) ? fontPath : "Helvetica-Bold");
      doc.text(`ŁĄCZNY PRZYCHÓD Z FILTROWANIA: ${totalRevenue.toFixed(2)} PLN`);
    }

    // =========================================================================
    // RAPORT 2: STANDARDOWY (STRUKTURA Z UWZGLĘDNIENIEM KRYTERIÓW)
    // =========================================================================
    else if (reportType === "employees_hierarchy") {
      doc
        .fontSize(16)
        .text("Struktura Organizacyjna Pracowników", { underline: true })
        .moveDown();

      const emps = await pool.query(
        `
        SELECT p.first_name, p.last_name, p.email, e.salary, e.hire_date,
               pm.last_name as manager_name, pm.first_name as manager_first, d.name as dept
        FROM employees e
        JOIN persons p ON e.person_id = p.id
        LEFT JOIN employees m ON e.manager_id = m.person_id
        LEFT JOIN persons pm ON m.person_id = pm.id
        JOIN departments d ON e.department_id = d.id
        WHERE e.hire_date >= $1 AND e.hire_date <= $2 AND e.salary >= $3
        ORDER BY d.name, e.salary DESC
      `,
        [start, end, minVal],
      );

      if (emps.rows.length === 0)
        doc.text(
          "Brak pracowników spełniających kryteria zatrudnienia i zarobków.",
        );

      let currentDept = "";

      // Definiujemy jedną czcionkę z polskimi znakami dla całego dokumentu
      const myFont = fs.existsSync(fontPath) ? fontPath : "Helvetica";

      emps.rows.forEach((e) => {
        // Zabezpieczenie przed ucięciem pracownika - przeniesienie całości na nową stronę
        if (doc.y > 680) doc.addPage();

        // 1. Sekcja: NAGŁÓWEK DZIAŁU
        if (e.dept !== currentDept) {
          currentDept = e.dept;
          doc.moveDown(1);

          const currentY = doc.y; // Pobieramy absolutną wysokość

          // Rysujemy tło i ustawiamy tekst "sztywno" względem tła
          doc.rect(50, currentY, 500, 25).fillAndStroke("#e0e0e0", "#e0e0e0");
          doc
            .fillColor("#333")
            .font(myFont)
            .fontSize(14)
            .text(currentDept.toUpperCase(), 60, currentY + 7); // +7 w dół od krawędzi prostokąta

          doc.y = currentY + 45; // Odstęp na dole nagłówka
        }

        // 2. Sekcja: SZCZEGÓŁY PRACOWNIKA
        const empY = doc.y; // Zapisujemy pozycję Y konkretnego pracownika

        // Kropka punktora
        doc.circle(60, empY + 6, 2).fill("black");

        // Pogrubione Imię i Nazwisko
        doc
          .fillColor("black")
          .font(myFont)
          .fontSize(12)
          .text(`${e.first_name} ${e.last_name}`, 70, empY);

        // Szare detale pod spodem
        doc.font(myFont).fontSize(10).fillColor("#555");

        const managerInfo = e.manager_name
          ? `Przełożony: ${e.manager_name}`
          : "STANOWISKO KIEROWNICZE";
        doc.text(
          `Zatrudniony: ${new Date(e.hire_date).toLocaleDateString()} | Pensja: ${e.salary} PLN | ${managerInfo}`,
          70,
          empY + 14,
        );

        // Przesunięcie kursora dla następnego pracownika w pętli
        doc.y = empY + 40;
      });
    }

    // =========================================================================
    // RAPORT 3: Z WYKRESEM (Pkt 6b.4)
    // =========================================================================
    else if (reportType === "financial_chart") {
      doc
        .fontSize(16)
        .text("Wykres Finansowy (Top Spektakle)", {
          align: "center",
          underline: true,
        })
        .moveDown(2);

      const chartData = await pool.query(
        `
          SELECT s.title, COALESCE(SUM(t.final_price),0) as total
          FROM spectacles s
          JOIN seances se ON se.spectacle_id = s.id
          JOIN reservations r ON r.seance_id = se.id
          JOIN tickets t ON t.reservation_id = r.id
          WHERE se.start_time >= $1 AND se.start_time <= $2
          GROUP BY s.title 
          HAVING COALESCE(SUM(t.final_price),0) >= $3
          ORDER BY total DESC LIMIT 5
      `,
        [start, end, minVal],
      ); // Użycie 3 kryteriów w SQL

      if (chartData.rows.length === 0) {
        doc.text("Brak danych finansowych dla podanych kryteriów.");
      } else {
        const chartHeight = 300;
        const chartWidth = 400;
        const startX = 100;
        const startY = doc.y + 20;
        const bottomY = startY + chartHeight;
        const maxVal =
          Math.max(...chartData.rows.map((r) => parseFloat(r.total))) * 1.1 ||
          1000;

        doc.rect(startX, startY, chartWidth, chartHeight).fill("#fcfcfc");
        doc.lineWidth(0.5);

        for (let i = 0; i <= 5; i++) {
          const value = (maxVal / 5) * i;
          const lineY = bottomY - (chartHeight / 5) * i;
          doc
            .strokeColor("#e0e0e0")
            .moveTo(startX, lineY)
            .lineTo(startX + chartWidth, lineY)
            .stroke();
          doc
            .fillColor("#555")
            .fontSize(9)
            .text(Math.round(value) + " PLN", startX - 60, lineY - 3, {
              width: 50,
              align: "right",
            });
        }

        const barWidth = 40;
        const gap =
          (chartWidth - chartData.rows.length * barWidth) /
          (chartData.rows.length + 1);

        chartData.rows.forEach((row, i) => {
          const val = parseFloat(row.total);
          const barHeight = (val / maxVal) * chartHeight;
          const x = startX + gap + i * (barWidth + gap);
          const y = bottomY - barHeight;

          doc.rect(x + 3, y + 3, barWidth, barHeight).fill("#dddddd"); // Cień
          doc.rect(x, y, barWidth, barHeight).fill("#2980b9"); // Słupek
          doc
            .fillColor("black")
            .fontSize(10)
            .text(val.toFixed(0), x - 5, y - 15, {
              width: barWidth + 10,
              align: "center",
            });

          let title =
            row.title.length > 12
              ? row.title.substring(0, 10) + "..."
              : row.title;
          doc
            .fillColor("#333")
            .fontSize(9)
            .text(title, x - 10, bottomY + 10, {
              width: barWidth + 20,
              align: "center",
            });
        });
        doc
          .rect(startX, startY, chartWidth, chartHeight)
          .strokeColor("#333")
          .lineWidth(1)
          .stroke();
      }
    }

    // =========================================================================
    // RAPORT 4: W FORMIE FORMULARZA (Pkt 6b.5 i 6b.1 - czwarty raport)
    // =========================================================================
    else if (reportType === "invoice_form") {
      const invData = await pool.query(
        `
          SELECT r.id as res_id, p.first_name, p.last_name, p.email, r.reservation_date,
                 s.title, se.start_time, COALESCE(SUM(t.final_price),0) as total_price
          FROM reservations r
          JOIN users u ON r.user_id = u.person_id
          JOIN persons p ON u.person_id = p.id
          JOIN seances se ON r.seance_id = se.id
          JOIN spectacles s ON se.spectacle_id = s.id
          LEFT JOIN tickets t ON t.reservation_id = r.id
          WHERE r.reservation_date >= $1 AND r.reservation_date <= $2
          GROUP BY r.id, p.first_name, p.last_name, p.email, r.reservation_date, s.title, se.start_time
          HAVING COALESCE(SUM(t.final_price),0) >= $3
          ORDER BY r.reservation_date DESC LIMIT 4
      `,
        [start, end, minVal],
      );

      if (invData.rows.length === 0) {
        doc
          .fontSize(12)
          .text("Brak rezerwacji spełniających podane kryteria daty i kwoty.");
      }

      // Rysujemy formularze dla każdej pobranej rezerwacji
      invData.rows.forEach((row, index) => {
        // Złamanie strony jeśli brakuje miejsca na kolejny bloczek
        if (index > 0 && doc.y > 550) doc.addPage();

        const formTop = doc.y + 10;

        // Zewnętrzna ramka formularza
        doc
          .lineWidth(2)
          .rect(50, formTop, 500, 180)
          .strokeColor("#333")
          .stroke();
        doc.lineWidth(1);

        // Tytuł formularza (Wymuszony czarny kolor)
        doc
          .fillColor("black")
          .fontSize(14)
          .font(fs.existsSync(fontPath) ? fontPath : "Helvetica-Bold")
          .text(
            "FORMULARZ POTWIERDZENIA REZERWACJI NR: " + row.res_id,
            60,
            formTop + 15,
          );
        doc
          .moveTo(50, formTop + 40)
          .lineTo(550, formTop + 40)
          .stroke(); // Linia oddzielająca

        doc.font(fs.existsSync(fontPath) ? fontPath : "Helvetica");

        // Sekcja: DANE KLIENTA (Rysowanie "pól" do wypełnienia)
        doc
          .fontSize(10)
          .fillColor("#555")
          .text("DANE KLIENTA:", 60, formTop + 55);
        doc.rect(60, formTop + 70, 220, 25).fillAndStroke("#f9f9f9", "#333");
        doc
          .fillColor("black")
          .text(`${row.first_name} ${row.last_name}`, 65, formTop + 78);

        doc.fillColor("#555").text("ADRES E-MAIL:", 300, formTop + 55);
        doc.rect(300, formTop + 70, 230, 25).fillAndStroke("#f9f9f9", "#333");
        doc
          .fillColor("black")
          .text(row.email || "Brak podanego e-maila", 305, formTop + 78);

        // Sekcja: SZCZEGÓŁY WYDARZENIA
        doc.fillColor("#555").text("WYDARZENIE:", 60, formTop + 110);
        doc.rect(60, formTop + 125, 330, 25).fillAndStroke("#e8f4f8", "#333");
        doc
          .fillColor("black")
          .text(
            `${row.title} (Data: ${new Date(row.start_time).toLocaleString()})`,
            65,
            formTop + 133,
          );

        // Sekcja: OPŁATA
        doc.fillColor("#555").text("DO ZAPŁATY (PLN):", 410, formTop + 110);
        doc.rect(410, formTop + 125, 120, 25).fillAndStroke("#fff", "#333"); // Wypełnienie na biało

        // POPRAWKA BŁĘDU: Ustawienie koloru czcionki na czarny przed wpisaniem ceny!
        doc
          .fillColor("black")
          .font(fs.existsSync(fontPath) ? fontPath : "Helvetica-Bold")
          .fontSize(12)
          .text(
            `${parseFloat(row.total_price).toFixed(2)} PLN`,
            415,
            formTop + 131,
          );

        // Ustawienie kursora "na sztywno" na dole wygenerowanego formularza przed kolejną iteracją
        doc.y = formTop + 200;
      });
    }
  } catch (err) {
    doc.fillColor("red").text("Błąd generowania raportu SQL: " + err.message);
  }
  doc.end();
});

// ==========================================
// 3. ADMIN DASHBOARD I ZARZĄDZANIE (CRUD)
// ==========================================

// --- PANEL GŁÓWNY ADMINA ---
app.get("/admin", async (req, res) => {
  try {
    let fromDateRaw = req.query.from
      ? moment(req.query.from)
      : moment().startOf("year");
    let toDateRaw = req.query.to
      ? moment(req.query.to)
      : moment().endOf("year");
    const fromDate = fromDateRaw.format("YYYY-MM-DD");
    const toDate = toDateRaw.format("YYYY-MM-DD");

    const spectacles = await pool.query(`
        SELECT s.*, g.name as genre_name 
        FROM spectacles s LEFT JOIN genres g ON s.genre_id = g.id 
        ORDER BY s.id DESC
    `);

    const seances = await pool.query(`
        SELECT se.id, s.title, se.start_time, se.base_price, h.name as hall 
        FROM seances se 
        JOIN spectacles s ON se.spectacle_id = s.id 
        JOIN halls h ON se.hall_id = h.id 
        ORDER BY se.start_time
    `);

    const financialView = await pool.query(`
        SELECT title, sold_tickets as tickets_sold, revenue 
        FROM v_financial_report ORDER BY revenue DESC LIMIT 10
    `);

    const employees = await pool.query(`
      SELECT p.first_name, p.last_name, e.* FROM employees e 
      JOIN persons p ON e.person_id = p.id 
      ORDER BY p.last_name LIMIT 5
    `);

    const chartQuery = `
        SELECT TO_CHAR(se.start_time, 'YYYY-MM-DD') as day, COALESCE(SUM(t.final_price),0) as revenue
        FROM tickets t JOIN reservations r ON t.reservation_id = r.id
        JOIN seances se ON r.seance_id = se.id
        WHERE se.start_time >= $1 AND se.start_time <= $2
        GROUP BY day ORDER BY day ASC
    `;
    const chartData = await pool.query(chartQuery, [
      fromDate,
      toDate + " 23:59:59",
    ]);

    res.render("admin_dashboard", {
      spectacles: spectacles.rows,
      seances: seances.rows,
      report: financialView.rows,
      employees: employees.rows,
      chartData: chartData.rows,
      moment,
      query: { from: fromDate, to: toDate },
    });
  } catch (err) {
    res.status(500).send("Błąd Admin: " + err.message);
  }
});

// --- ZARZĄDZANIE SPEKTAKLAMI (Przywrócone) ---

app.get("/admin/spectacle/new", async (req, res) => {
  const genres = await pool.query("SELECT * FROM genres ORDER BY name");
  res.render("admin_spectacle_form", { genres: genres.rows });
});

app.post("/admin/spectacle", upload.single("poster"), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { title, description, duration, genre_id } = req.body;

    const insertRes = await client.query(
      "INSERT INTO spectacles (title, description, duration_minutes, poster_url, genre_id, premiere_date) VALUES ($1, $2, $3, 'temp', $4, NOW()) RETURNING id",
      [title, description, duration, genre_id],
    );
    const newId = insertRes.rows[0].id;

    let finalPosterUrl = "/images/default-poster.png";
    if (req.file) finalPosterUrl = "/images/" + req.file.filename;

    await client.query("UPDATE spectacles SET poster_url = $1 WHERE id = $2", [
      finalPosterUrl,
      newId,
    ]);
    await client.query("COMMIT");
    res.redirect("/admin");
  } catch (err) {
    await client.query("ROLLBACK");
    res.status(500).send("Błąd: " + err.message);
  } finally {
    client.release();
  }
});

app.get("/admin/spectacle/edit/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const specRes = await pool.query("SELECT * FROM spectacles WHERE id = $1", [
      id,
    ]);
    if (specRes.rows.length === 0)
      return res.status(404).send("Nie znaleziono");

    const spectacle = specRes.rows[0];
    const genresRes = await pool.query("SELECT * FROM genres ORDER BY name");

    const currentCastRes = await pool.query(
      `
      SELECT sa.actor_id, p.first_name, p.last_name, sa.role_name
      FROM spectacle_actors sa 
      JOIN actors a ON sa.actor_id = a.person_id
      JOIN persons p ON a.person_id = p.id
      WHERE sa.spectacle_id = $1
    `,
      [id],
    );

    const allActorsRes = await pool.query(
      `
      SELECT a.person_id as id, p.first_name, p.last_name 
      FROM actors a 
      JOIN persons p ON a.person_id = p.id
      WHERE a.person_id NOT IN (SELECT actor_id FROM spectacle_actors WHERE spectacle_id = $1)
      ORDER BY p.last_name
    `,
      [id],
    );

    res.render("admin_spectacle_edit", {
      spectacle: spectacle,
      genres: genresRes.rows,
      currentCast: currentCastRes.rows,
      availableActors: allActorsRes.rows,
      moment,
    });
  } catch (err) {
    res.status(500).send(err.message);
  }
});

app.post(
  "/admin/spectacle/edit/:id",
  upload.single("poster"),
  async (req, res) => {
    try {
      const { id } = req.params;
      const { title, description, duration, genre_id } = req.body;

      if (req.file) {
        const newPosterUrl = "/images/" + req.file.filename;
        await pool.query(
          "UPDATE spectacles SET title=$1, description=$2, duration_minutes=$3, genre_id=$4, poster_url=$5 WHERE id=$6",
          [title, description, duration, genre_id, newPosterUrl, id],
        );
      } else {
        await pool.query(
          "UPDATE spectacles SET title=$1, description=$2, duration_minutes=$3, genre_id=$4 WHERE id=$5",
          [title, description, duration, genre_id, id],
        );
      }
      res.redirect("/admin");
    } catch (err) {
      res.status(500).send(err.message);
    }
  },
);

app.post("/admin/spectacle/:id/add-actor", async (req, res) => {
  try {
    const { actor_id, role_name } = req.body;
    await pool.query(
      "INSERT INTO spectacle_actors (spectacle_id, actor_id, role_name) VALUES ($1, $2, $3)",
      [req.params.id, actor_id, role_name],
    );
    res.redirect(`/admin/spectacle/edit/${req.params.id}`);
  } catch (err) {
    res.status(500).send(err.message);
  }
});

app.post("/admin/spectacle/:id/remove-actor", async (req, res) => {
  try {
    await pool.query(
      "DELETE FROM spectacle_actors WHERE spectacle_id = $1 AND actor_id = $2",
      [req.params.id, req.body.actor_id],
    );
    res.redirect(`/admin/spectacle/edit/${req.params.id}`);
  } catch (err) {
    res.status(500).send(err.message);
  }
});

// --- ZARZĄDZANIE SEANSAMI (Przywrócone) ---

app.get("/admin/seance/new", async (req, res) => {
  const specs = await pool.query("SELECT * FROM spectacles");
  const halls = await pool.query("SELECT * FROM halls");
  res.render("admin_seance_form", {
    spectacles: specs.rows,
    halls: halls.rows,
  });
});

app.post("/admin/seance", async (req, res) => {
  const { spectacle_id, hall_id, start_time, price } = req.body;
  if (!start_time) return res.status(400).send("Brak daty");
  try {
    await pool.query(
      "INSERT INTO seances (spectacle_id, hall_id, start_time, base_price) VALUES ($1, $2, $3, $4)",
      [spectacle_id, hall_id, start_time, price],
    );
    res.redirect("/admin");
  } catch (err) {
    res.status(500).send(err.message);
  }
});

app.get("/admin/seance/edit/:id", async (req, res) => {
  try {
    const seanceRes = await pool.query("SELECT * FROM seances WHERE id=$1", [
      req.params.id,
    ]);
    if (seanceRes.rows.length === 0) return res.status(404).send("Brak seansu");
    const specs = await pool.query("SELECT id, title FROM spectacles");
    const halls = await pool.query("SELECT id, name FROM halls");
    const seance = seanceRes.rows[0];
    seance.formatted_time = moment(seance.start_time).format(
      "YYYY-MM-DDTHH:mm",
    );
    res.render("admin_seance_edit", {
      seance,
      spectacles: specs.rows,
      halls: halls.rows,
    });
  } catch (err) {
    res.status(500).send(err.message);
  }
});

app.post("/admin/seance/edit/:id", async (req, res) => {
  const { spectacle_id, hall_id, start_time, price } = req.body;
  try {
    await pool.query(
      "UPDATE seances SET spectacle_id=$1, hall_id=$2, start_time=$3, base_price=$4 WHERE id=$5",
      [spectacle_id, hall_id, start_time, price, req.params.id],
    );
    res.redirect("/admin");
  } catch (err) {
    res.status(500).send(err.message);
  }
});

// --- ZARZĄDZANIE AKTORAMI (Przywrócone) ---

app.get("/admin/actors", async (req, res) => {
  const query = `
    SELECT a.person_id as id, p.first_name, p.last_name, a.base_salary, COUNT(sa.spectacle_id) as roles_count 
    FROM actors a 
    JOIN persons p ON a.person_id = p.id
    LEFT JOIN spectacle_actors sa ON a.person_id = sa.actor_id 
    GROUP BY a.person_id, p.first_name, p.last_name 
    ORDER BY p.last_name ASC`;
  const { rows } = await pool.query(query);
  res.render("admin_actors_list", { actors: rows });
});

app.get("/admin/actors/new", (req, res) => {
  res.render("admin_actor_form");
});

app.post("/admin/actors", async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { first_name, last_name, bio, base_salary, email } = req.body;
    const personRes = await client.query(
      "INSERT INTO persons (first_name, last_name, email) VALUES ($1, $2, $3) RETURNING id",
      [first_name, last_name, email || null],
    );
    const newPersonId = personRes.rows[0].id;

    // Potem aktora
    await client.query(
      "INSERT INTO actors (person_id, bio, base_salary) VALUES ($1, $2, $3)",
      [newPersonId, bio, base_salary || 3000],
    );
    await client.query("COMMIT");
    res.redirect("/admin/actors");
  } catch (err) {
    await client.query("ROLLBACK");
    res.status(500).send(err.message);
  } finally {
    client.release();
  }
});

app.get("/admin/actors/edit/:id", async (req, res) => {
  const { rows } = await pool.query(
    `
    SELECT a.person_id as id, p.first_name, p.last_name, p.email, a.base_salary, a.bio 
    FROM actors a 
    JOIN persons p ON a.person_id = p.id 
    WHERE a.person_id=$1`,
    [req.params.id],
  );
  if (rows.length === 0) return res.status(404).send("Brak aktora");
  res.render("admin_actor_edit", { actor: rows[0] });
});

app.post("/admin/actors/edit/:id", async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { first_name, last_name, base_salary, bio, email } = req.body;

    await client.query(
      "UPDATE persons SET first_name=$1, last_name=$2, email=$3 WHERE id=$4",
      [first_name, last_name, email || null, req.params.id],
    );

    await client.query(
      "UPDATE actors SET base_salary=$1, bio=$2 WHERE person_id=$3",
      [base_salary, bio, req.params.id],
    );
    await client.query("COMMIT");
    res.redirect("/admin/actors");
  } catch (err) {
    await client.query("ROLLBACK");
    res.status(500).send(err.message);
  } finally {
    client.release();
  }
});

// --- FUNKCJE PROCEDURALNE (Pkt 4 - Call) ---
app.post("/admin/update-prices", async (req, res) => {
  try {
    // Pobieramy wartość procentową z formularza (może być ujemna dla obniżki)
    const percentage = parseFloat(req.body.percentage);

    // Wywołujemy procedurę SQL z parametrem
    await pool.query("CALL update_seance_prices($1)", [percentage]);

    res.redirect("/admin");
  } catch (err) {
    res.status(500).send("Błąd procedury: " + err.message);
  }
});

// ==========================================
// 4. STRONA PUBLICZNA (Index, Bilet, Rezerwacja)
// ==========================================

app.get("/", async (req, res) => {
  try {
    const selectedGenre = req.query.genre;
    let queryText = `
        SELECT s.*, g.name as genre_name 
        FROM spectacles s 
        LEFT JOIN genres g ON s.genre_id = g.id
    `;
    const queryParams = [];
    if (selectedGenre) {
      queryText += " WHERE s.genre_id = $1";
      queryParams.push(selectedGenre);
    }
    queryText += " ORDER BY s.premiere_date DESC";

    const specs = await pool.query(queryText, queryParams);
    const genres = await pool.query("SELECT * FROM genres ORDER BY name");

    res.render("index", {
      spectacles: specs.rows,
      genres: genres.rows,
      selectedGenre: selectedGenre || null,
    });
  } catch (err) {
    res.status(500).send(err.message);
  }
});

app.get("/spectacle/:id", async (req, res) => {
  try {
    const { id } = req.params;

    // POPRAWKA: Zmieniono 'as genre' na 'as genre_name' oraz JOIN na LEFT JOIN
    const spec = await pool.query(
      "SELECT s.*, g.name as genre_name FROM spectacles s LEFT JOIN genres g ON s.genre_id = g.id WHERE s.id=$1",
      [id],
    );

    const seances = await pool.query(
      "SELECT s.*, h.name as hall_name FROM seances s JOIN halls h ON s.hall_id=h.id WHERE s.spectacle_id=$1 AND s.start_time > NOW()",
      [id],
    );

    const actors = await pool.query(
      `
      SELECT p.first_name, p.last_name, a.*, sa.role_name 
      FROM actors a 
      JOIN persons p ON a.person_id = p.id
      JOIN spectacle_actors sa ON a.person_id=sa.actor_id 
      WHERE sa.spectacle_id=$1
    `,
      [id],
    );

    const reviews = await pool.query(
      "SELECT r.*, u.username FROM reviews r JOIN users u ON r.user_id=u.person_id WHERE r.spectacle_id=$1",
      [id],
    );

    if (spec.rows.length === 0) return res.status(404).send("Brak spektaklu");

    res.render("spectacle", {
      spectacle: spec.rows[0],
      seances: seances.rows,
      actors: actors.rows,
      reviews: reviews.rows,
      moment,
    });
  } catch (err) {
    res.send(err.message);
  }
});

app.post("/spectacle/:id/review", async (req, res) => {
  await pool.query(
    "INSERT INTO reviews (user_id, spectacle_id, rating, comment) VALUES ($1, $2, $3, $4)",
    [req.session.user.id, req.params.id, req.body.rating, req.body.comment],
  );
  res.redirect("/spectacle/" + req.params.id);
});

app.get("/book/:seanceId", async (req, res) => {
  const seance = await pool.query(
    `SELECT se.*, s.title, h.name as hall_name 
         FROM seances se 
         JOIN spectacles s ON se.spectacle_id = s.id 
         JOIN halls h ON se.hall_id = h.id 
         WHERE se.id=$1`,
    [req.params.seanceId],
  );
  const seats = await pool.query(
    "SELECT * FROM seats WHERE hall_id=$1 ORDER BY grid_y, grid_x",
    [seance.rows[0].hall_id],
  );
  const taken = await pool.query(
    "SELECT seat_id FROM tickets t JOIN reservations r ON t.reservation_id=r.id WHERE r.seance_id=$1",
    [req.params.seanceId],
  );

  res.render("booking", {
    seance: seance.rows[0],
    seats: seats.rows,
    bookedIds: taken.rows.map((r) => r.seat_id), // Poprawka nazwy zmiennej
    moment,
  });
});

app.post("/book", async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { seanceId, selectedSeats } = req.body;
    if (!selectedSeats) throw new Error("Nie wybrano miejsc!");

    const seats = Array.isArray(selectedSeats)
      ? selectedSeats
      : [selectedSeats];

    const resRes = await client.query(
      "INSERT INTO reservations (user_id, seance_id) VALUES ($1, $2) RETURNING id",
      [req.session.user.id, seanceId],
    );
    const resId = resRes.rows[0].id;

    const priceRes = await client.query(
      "SELECT base_price FROM seances WHERE id=$1",
      [seanceId],
    );
    const price = priceRes.rows[0].base_price;

    for (let sid of seats) {
      await client.query(
        "INSERT INTO tickets (reservation_id, seat_id, final_price, ticket_token) VALUES ($1, $2, $3, md5(random()::text))",
        [resId, sid, price],
      );
    }
    await client.query("COMMIT");
    res.redirect("/");
  } catch (e) {
    await client.query("ROLLBACK");
    res.send("Błąd rezerwacji: " + e.message);
  } finally {
    client.release();
  }
});

// Start serwera
app.listen(port, () => {
  console.log(`Aplikacja działa\nPort:${port}`);
});
