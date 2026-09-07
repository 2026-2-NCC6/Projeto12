> Readme destinado a descrição do módulo do projeto e documentar os passos de execução e desenvolvimento

# Firmware (ESP32 IoT)

Projeto [PlatformIO](https://platformio.org/) (não usa a Arduino IDE — ver ADR na skill do projeto).

## Instruções de Desenvolvimento

Com a [extensão PlatformIO](https://platformio.org/install/ide?install=vscode) instalada (VS Code) ou a [CLI do PlatformIO](https://docs.platformio.org/en/latest/core/installation/index.html):

```bash
# Compilar
pio run

# Compilar e gravar no ESP32 conectado por USB
pio run --target upload

# Abrir o monitor serial (115200 bps)
pio device monitor
```

## Bibliotecas

- Nenhuma além do framework Arduino por enquanto (MPU6050, DFPlayer Mini e NimBLE-Arduino entram quando as features correspondentes forem implementadas)

## Ferramentas

- ESP32 DevKit v1
- Sensor MPU6050
