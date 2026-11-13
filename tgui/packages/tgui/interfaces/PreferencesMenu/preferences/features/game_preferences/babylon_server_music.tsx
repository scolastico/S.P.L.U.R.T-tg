import { type Feature, FeatureSliderInput } from '../base';

export const babylon_server_music: Feature<number> = {
  name: 'Server music volume',
  category: 'SOUND',
  description: `
    Volume of the music this server plays in the world (0 turns it off).
    Mute it when you record or stream: the tracks may be licensed for this
    server only. Also toggled with "Toggle Server Music" in the OOC tab.
  `,
  component: FeatureSliderInput,
};
