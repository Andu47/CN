#!/bin/bash

MODUL="cache_top"

rm -f ${MODUL}_sim  # Asta ne asigura ca nu rulam fantome

# Aceasta este o linie de comentariu. Urmează compilarea:
echo "Compilez codul..."
iverilog -g2012 -o ${MODUL}_sim ../tb/tb_${MODUL}.v ../src/*.v ../src/datapath/*.v ../src/storage/*.v

# Rularea simulării:
echo "Rulez simularea..."
vvp ${MODUL}_sim

# Opțional: Deschide GTKWave automat (poți șterge linia asta dacă nu vrei)
# gtkwave fac_waves.vcd