-- Legt die Datenbank an, falls sie noch nicht existiert (laeuft gegen "master").
IF DB_ID(N'msv_dwh') IS NULL
    CREATE DATABASE msv_dwh;
