# rae-invoices

A [Ruby][] program that serves a JSON API of electricity prices (€/kWh) in Greece scraped from the [official regulatory authority](https://www.raaey.gr/energeia/)

It can be useful for [Home Assistant][ha] setups to calculate the cost of energy consumption.

Relevant blog post with more details (Greek): <https://angelos.dev/2024/12/timologia-parochon-energeias-sto-home-assistant/>

[ruby]: https://www.ruby-lang.org/en/
[ha]: https://www.home-assistant.io/

## Demo

An online service is available at <https://rae-invoices.fly.dev>

## Installation

You need to have [Ruby][] installed in your system.

```shell
git clone https://github.com/agorf/rae-invoices.git
cd rae-invoices
bundle install
```

## Run

Issue `bundle exec rackup` from inside the project directory and visit <https://127.0.0.1:9292>

## License

[MIT](https://github.com/agorf/greeklish_iso843/blob/master/LICENSE.txt)

## Author

[Angelos Orfanakos](https://angelos.dev/)
