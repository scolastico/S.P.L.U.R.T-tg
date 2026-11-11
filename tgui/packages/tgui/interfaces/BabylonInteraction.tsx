// Babylon-only interaction list (opened by modular_babylon/code/sfw.dm).
// It replaces the SPLURT MobInteraction window, whose extra tabs carry ERP
// content; ordinary SPLURT builds never open this interface.
import { useState } from 'react';
import { Button, Input, NoticeBox, Section, Stack } from 'tgui-core/components';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  self: string;
  ref_self: string;
  ref_user: string;
  block_interact: boolean;
  categories: string[];
  interactions: Record<string, string[]>;
  descriptions: Record<string, string>;
  colors: Record<string, string>;
};

export const BabylonInteraction = () => {
  const { act, data } = useBackend<Data>();
  const {
    self,
    ref_self,
    ref_user,
    block_interact,
    categories = [],
    interactions = {},
    descriptions = {},
    colors = {},
  } = data;
  const [searchText, setSearchText] = useState('');
  const search = searchText.toLowerCase();

  const sections = categories
    .map((category) => ({
      category,
      names: (interactions[category] || []).filter((name) =>
        name.toLowerCase().includes(search),
      ),
    }))
    .filter(({ names }) => names.length > 0);

  return (
    <Window width={400} height={500} title="Interaction">
      <Window.Content scrollable>
        <Section title={`Interacting with ${self}`}>
          <Stack vertical>
            <Stack.Item>
              <Input
                fluid
                placeholder="Search for an interaction"
                onChange={(value) => setSearchText(value)}
              />
            </Stack.Item>
            {!!block_interact && (
              <Stack.Item>
                <NoticeBox>Unable to interact right now.</NoticeBox>
              </Stack.Item>
            )}
          </Stack>
        </Section>
        {sections.map(({ category, names }) => (
          <Section key={category} title={category}>
            {names.map((name) => (
              <Button
                key={name}
                fluid
                color={block_interact ? 'grey' : colors[name]}
                tooltip={descriptions[name]}
                disabled={block_interact}
                onClick={() =>
                  act('interact', {
                    interaction: name,
                    selfref: ref_self,
                    userref: ref_user,
                  })
                }
              >
                {name}
              </Button>
            ))}
          </Section>
        ))}
        {sections.length === 0 && (
          <NoticeBox>No interactions available.</NoticeBox>
        )}
      </Window.Content>
    </Window>
  );
};
