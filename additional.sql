--Widok laczacy dane klientow z adresami
CREATE VIEW View_DaneKlienta AS
SELECT k.idKlient, k.imie, k.nazwisko, k.email, k.nr_telefonu, a.ulica, a.kod_pocztowy, a.miasto, a.nr_domu
FROM Klient k
JOIN Adres a ON k.idAdres = a.idAdres;

--Widok szczegolow zamowienia
CREATE VIEW View_SzczegolyZamowienia AS
SELECT z.idZamowienie, z.data_zamowienia, k.imie, k.nazwisko, m.nazwa, pz.ilosc, (pz.cena_pozycji * pz.ilosc) AS calkowity_koszt
FROM Zamowienie z
JOIN Klient k ON z.idKlient = k.idKlient
JOIN Pozycja_Zamowienia pz ON z.idZamowienie = pz.idZamowienie
JOIN Menu m ON pz.idMenu = m.idMenu;

--Widok srednia ocena produktow w kazdej kategorii
CREATE VIEW View_OcenyKategorii AS
SELECT kat.nazwa_kategorii, AVG(r.ocena) AS srednia_ocena
FROM Kategoria kat
JOIN Menu m ON kat.idKategoria = m.idKategoria
JOIN Recenzja r ON m.idMenu = r.idMenu
GROUP BY kat.nazwa_kategorii;

SELECT * FROM View_DaneKlienta;
SELECT * FROM View_SzczegolyZamowienia;
SELECT * FROM View_OcenyKategorii;

--Funkcja obliczajaja sume transakcji dokonanych przez danego klienta
CREATE OR REPLACE FUNCTION ObliczCalkowityObrotKlienta(id_klienta INTEGER)
RETURNS NUMERIC AS $$
DECLARE
    calkowity_obrot NUMERIC;
BEGIN
    SELECT SUM(z.laczna_kwota)
    INTO calkowity_obrot
    FROM Zamowienie z
    WHERE z.idKlient = id_klienta;
    
    RETURN calkowity_obrot;
END;
$$ LANGUAGE plpgsql;

SELECT ObliczCalkowityObrotKlienta(1); 

--Funkcja analizy preferencji klientow (ulubione kategorie na podstawie zamowien i ocen)
CREATE OR REPLACE FUNCTION AnalizaPreferencjiKlientow()
RETURNS TABLE(id_klienta INTEGER, imie VARCHAR, nazwisko VARCHAR, preferowana_kategoria VARCHAR, srednia_ocena NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT k.idKlient, k.imie, k.nazwisko, kat.nazwa_kategorii AS preferowana_kategoria, AVG(r.ocena) AS srednia_ocena
    FROM Klient k
    JOIN Zamowienie z ON k.idKlient = z.idKlient
    JOIN Pozycja_Zamowienia pz ON z.idZamowienie = pz.idZamowienie
    JOIN Menu m ON pz.idMenu = m.idMenu
    JOIN Kategoria kat ON m.idKategoria = kat.idKategoria
    JOIN Recenzja r ON m.idMenu = r.idMenu AND k.idKlient = r.idKlient
    GROUP BY k.idKlient, k.imie, k.nazwisko, kat.nazwa_kategorii
    HAVING AVG(r.ocena) > 3
    ORDER BY srednia_ocena DESC;
END;
$$ LANGUAGE plpgsql;

SELECT * FROM AnalizaPreferencjiKlientow();

--Procedura dodawania zamowienia
CREATE OR REPLACE PROCEDURE DodajZamowienie(
    p_idKlient INTEGER,
    p_idMenu INTEGER[],
    p_ilosc INTEGER[]
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_idZamowienie INTEGER;
    i INTEGER;
BEGIN
    INSERT INTO Zamowienie (idKlient)
    VALUES (p_idKlient)
    RETURNING idZamowienie INTO v_idZamowienie;

    i := 1;
    WHILE i <= array_length(p_idMenu, 1) LOOP
        INSERT INTO Pozycja_Zamowienia (idZamowienie, idMenu, ilosc, cena_pozycji)
        SELECT v_idZamowienie, p_idMenu[i], p_ilosc[i], cena
        FROM Menu 
        WHERE idMenu = p_idMenu[i];
        i := i + 1;
    END LOOP;

    UPDATE Zamowienie 
    SET laczna_kwota = (
        SELECT SUM(cena_pozycji * ilosc)
        FROM Pozycja_Zamowienia
        WHERE idZamowienie = v_idZamowienie
    )
    WHERE idZamowienie = v_idZamowienie;
END;
$$;

CALL DodajZamowienie(1, ARRAY[1, 2], ARRAY[2, 1]);
SELECT * FROM Zamowienie;
SELECT * FROM Pozycja_Zamowienia WHERE idZamowienie = (SELECT MAX(idZamowienie) FROM Zamowienie);
SELECT laczna_kwota FROM Zamowienie WHERE idZamowienie = (SELECT MAX(idZamowienie) FROM Zamowienie);

--Procedura aktualizacji danych klienta
CREATE OR REPLACE PROCEDURE AktualizujDaneKlienta(
    p_idKlient INTEGER,
    p_nowyEmail VARCHAR,
    p_nowyNrTelefonu VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE Klient
    SET email = p_nowyEmail, nr_telefonu = p_nowyNrTelefonu
    WHERE idKlient = p_idKlient;
END;
$$;

CALL AktualizujDaneKlienta(1, 'nowy.email@example.com', '600700800');
SELECT imie, nazwisko, email, nr_telefonu FROM Klient WHERE idKlient = 1;

--Wyzwalacz sprawdzajacy cene (nie moze byc ujemna)
CREATE OR REPLACE FUNCTION check_price()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.cena < 0 THEN
    RAISE EXCEPTION 'Cena musi byc wartosci dodatniej.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER CheckPriceBeforeInsert
BEFORE INSERT ON Menu
FOR EACH ROW
EXECUTE FUNCTION check_price();


INSERT INTO Menu (idKategoria, nazwa, opis, cena, dostepnosc) VALUES (1, 'Testowa Pizza', 'Pizza dla testu', -10, true);


--Wyzwalacz aktualizujacy date ostatniego zamowienia
CREATE OR REPLACE FUNCTION update_last_order_date()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE Klient
  SET data_ostatniego_zamowienia = NEW.data_zamowienia
  WHERE idKlient = NEW.idKlient;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER UpdateLastOrderDate
AFTER INSERT ON Zamowienie
FOR EACH ROW
EXECUTE FUNCTION update_last_order_date();

INSERT INTO Zamowienie (idKlient, data_zamowienia, status_2, laczna_kwota) VALUES (1, '2024-06-15', true, 50.00);
SELECT data_ostatniego_zamowienia FROM Klient WHERE idKlient = 1;

--Wyzwalacz sprawdzajacy, czy email istnieje (nie mo�e si� powtarza�)
CREATE OR REPLACE FUNCTION check_email_before_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM Klient WHERE email = NEW.email) THEN
    RAISE EXCEPTION 'Email ju� istnieje w bazie danych.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER CheckEmailBeforeInsert
BEFORE INSERT ON Klient
FOR EACH ROW
EXECUTE FUNCTION check_email_before_insert();

INSERT INTO Klient (idAdres, imie, nazwisko, email, nr_telefonu) VALUES (1, 'Jan', 'Nowak', 'jan.kowalski@example.com', '999888777');

--Wyzwalacz logujacy zmiany stanowisk pracownikow
CREATE OR REPLACE FUNCTION log_employee_changes()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO Logi_Pracownikow (idPracownik, staryStanowisko, noweStanowisko, dataZmiany)
  VALUES (OLD.idPracownik, OLD.stanowisko, NEW.stanowisko, CURRENT_DATE);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER LogEmployeeChanges
AFTER UPDATE ON Pracownik
FOR EACH ROW
EXECUTE FUNCTION log_employee_changes();


UPDATE Pracownik SET stanowisko = 'Senior Manager' WHERE idPracownik = 1;
SELECT * FROM Logi_Pracownikow WHERE idPracownik = 1;


--Kursor 1 - Klienci z oczekujacymi zamowieniami
BEGIN TRANSACTION;

DECLARE cursor_pending_orders CURSOR FOR
    SELECT k.idKlient, k.imie, k.nazwisko, k.email, z.idZamowienie, z.data_zamowienia
    FROM Klient k
    JOIN Zamowienie z ON k.idKlient = z.idKlient
    WHERE z.status_2 = FALSE
    ORDER BY z.data_zamowienia DESC;

FETCH 5 FROM cursor_pending_orders;
MOVE 5 FROM cursor_pending_orders;
FETCH 5 FROM cursor_pending_orders;
FETCH ALL FROM cursor_pending_orders;

CLOSE cursor_pending_orders;

COMMIT TRANSACTION;

--Kursor 2 - Menu z recenzjami i srednia ocena
BEGIN TRANSACTION;

DECLARE cursor_menu_reviews CURSOR FOR
    SELECT m.idMenu, m.nazwa, m.opis, AVG(r.ocena) AS avg_rating, COUNT(r.idRecenzja) AS review_count
    FROM Menu m
    LEFT JOIN Recenzja r ON m.idMenu = r.idMenu
    GROUP BY m.idMenu, m.nazwa, m.opis
    HAVING COUNT(r.idRecenzja) > 0
    ORDER BY avg_rating DESC;

FETCH 5 FROM cursor_menu_reviews;
MOVE 5 FROM cursor_menu_reviews;
FETCH 5 FROM cursor_menu_reviews;
FETCH ALL FROM cursor_menu_reviews;

CLOSE cursor_menu_reviews;

COMMIT TRANSACTION;
