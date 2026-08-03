# Streamiau!

Some stream tools to use with StreamElements or others bots.

## Installation

- Clone the repository
- Configure `.env` file using `.env.example`.
- Install dependencies
```bash
shards install
```

## Usage
You need to load the environment variables, which will vary depending on the execution environment. A simple way to do this using zsh is:
```zsh
(set -a; source .env; crystal run src/streamiau.cr) # `crystal run src/streamiau.cr` with env vars
```

## Contributing

1. Fork it (<https://github.com/joseafga/streamiau/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [José Almeida](https://github.com/joseafga) - creator and maintainer
